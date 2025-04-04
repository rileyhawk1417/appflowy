import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/child_page_transaction_handler.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/date_transaction_handler.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/sub_page/sub_page_transaction_handler.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/transaction_handler/editor_transaction_handler.dart';
import 'package:appflowy/shared/clipboard_state.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'mention_transaction_handler.dart';

final _transactionHandlers = <EditorTransactionHandler>[
  if (FeatureFlag.inlineSubPageMention.isOn) ...[
    SubPageTransactionHandler(),
    ChildPageTransactionHandler(),
  ],
  DateTransactionHandler(),
];

/// Handles delegating transactions to appropriate handlers.
///
/// Such as the [ChildPageTransactionHandler] for inline child pages.
///
class EditorTransactionService extends StatefulWidget {
  const EditorTransactionService({
    super.key,
    required this.viewId,
    required this.editorState,
    required this.child,
  });

  final String viewId;
  final EditorState editorState;
  final Widget child;

  @override
  State<EditorTransactionService> createState() =>
      _EditorTransactionServiceState();
}

class _EditorTransactionServiceState extends State<EditorTransactionService> {
  StreamSubscription<EditorTransactionValue>? transactionSubscription;

  bool isUndoRedo = false;
  bool isPaste = false;
  bool isDraggingNode = false;
  bool isTurnInto = false;

  @override
  void initState() {
    super.initState();
    transactionSubscription =
        widget.editorState.transactionStream.listen(onEditorTransaction);
    EditorNotification.addListener(onEditorNotification);
  }

  @override
  void dispose() {
    EditorNotification.removeListener(onEditorNotification);
    transactionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void onEditorNotification(EditorNotificationType type) {
    if ([EditorNotificationType.undo, EditorNotificationType.redo]
        .contains(type)) {
      isUndoRedo = true;
    } else if (type == EditorNotificationType.paste) {
      isPaste = true;
    } else if (type == EditorNotificationType.dragStart) {
      isDraggingNode = true;
    } else if (type == EditorNotificationType.dragEnd) {
      isDraggingNode = false;
    } else if (type == EditorNotificationType.turnInto) {
      isTurnInto = true;
    }

    if (type == EditorNotificationType.undo) {
      undoCommand.execute(widget.editorState);
    } else if (type == EditorNotificationType.redo) {
      redoCommand.execute(widget.editorState);
    } else if (type == EditorNotificationType.exitEditing &&
        widget.editorState.selection != null) {
      // If the editor is disposed, we don't need to reset the selection.
      if (!widget.editorState.isDisposed) {
        widget.editorState.selection = null;
      }
    }
  }

  /// Collects all nodes of a certain type, including those that are nested.
  ///
  List<Node> collectMatchingNodes(
    Node node,
    String type, {
    bool livesInDelta = false,
  }) {
    final List<Node> matchingNodes = [];
    if (node.type == type) {
      matchingNodes.add(node);
    }

    if (livesInDelta && node.attributes[blockComponentDelta] != null) {
      final deltas = node.attributes[blockComponentDelta];
      if (deltas is List) {
        for (final delta in deltas) {
          if (delta['attributes'] != null &&
              delta['attributes'][type] != null) {
            matchingNodes.add(node);
          }
        }
      }
    }

    for (final child in node.children) {
      matchingNodes.addAll(
        collectMatchingNodes(
          child,
          type,
          livesInDelta: livesInDelta,
        ),
      );
    }

    return matchingNodes;
  }

  void onEditorTransaction(EditorTransactionValue event) {
    final time = event.$1;
    final transaction = event.$2;

    if (time == TransactionTime.before) {
      return;
    }

    final Map<String, dynamic> added = {
      for (final handler in _transactionHandlers)
        handler.type: handler.livesInDelta ? <MentionBlockData>[] : <Node>[],
    };
    final Map<String, dynamic> removed = {
      for (final handler in _transactionHandlers)
        handler.type: handler.livesInDelta ? <MentionBlockData>[] : <Node>[],
    };

    // based on the type of the transaction handler
    final uniqueTransactionHandlers = <String, EditorTransactionHandler>{};
    for (final handler in _transactionHandlers) {
      uniqueTransactionHandlers.putIfAbsent(handler.type, () => handler);
    }

    for (final op in transaction.operations) {
      if (op is InsertOperation) {
        for (final n in op.nodes) {
          for (final handler in uniqueTransactionHandlers.values) {
            if (handler.livesInDelta) {
              added[handler.type]!
                  .addAll(extractMentionsForType(n, handler.type));
            } else {
              added[handler.type]!
                  .addAll(collectMatchingNodes(n, handler.type));
            }
          }
        }
      } else if (op is DeleteOperation) {
        for (final n in op.nodes) {
          for (final handler in uniqueTransactionHandlers.values) {
            if (handler.livesInDelta) {
              removed[handler.type]!.addAll(
                extractMentionsForType(n, handler.type, false),
              );
            } else {
              removed[handler.type]!
                  .addAll(collectMatchingNodes(n, handler.type));
            }
          }
        }
      } else if (op is UpdateOperation) {
        final node = widget.editorState.getNodeAtPath(op.path);
        if (node == null) {
          continue;
        }

        if (op.attributes[blockComponentDelta] is! List ||
            op.oldAttributes[blockComponentDelta] is! List) {
          continue;
        }

        final deltaBefore =
            Delta.fromJson(op.oldAttributes[blockComponentDelta]);
        final deltaAfter = Delta.fromJson(op.attributes[blockComponentDelta]);

        final (add, del) = diffDeltas(deltaBefore, deltaAfter);

        bool fetchedMentions = false;
        for (final handler in _transactionHandlers) {
          if (!handler.livesInDelta || fetchedMentions) {
            continue;
          }

          if (add.isNotEmpty) {
            final mentionBlockDatas =
                getMentionBlockData(handler.type, node, add);

            added[handler.type]!.addAll(mentionBlockDatas);
          }

          if (del.isNotEmpty) {
            final mentionBlockDatas = getMentionBlockData(
              handler.type,
              node,
              del,
            );

            removed[handler.type]!.addAll(mentionBlockDatas);
          }

          fetchedMentions = true;
        }
      }
    }

    for (final handler in _transactionHandlers) {
      final additions = added[handler.type] ?? [];
      final removals = removed[handler.type] ?? [];

      if (additions.isEmpty && removals.isEmpty) {
        continue;
      }

      handler.onTransaction(
        context,
        widget.viewId,
        widget.editorState,
        additions,
        removals,
        isCut: context.read<ClipboardState>().isCut,
        isUndoRedo: isUndoRedo,
        isPaste: isPaste,
        isDraggingNode: isDraggingNode,
        isTurnInto: isTurnInto,
        parentViewId: widget.viewId,
      );
    }

    isUndoRedo = false;
    isPaste = false;
    isTurnInto = false;
  }

  /// Takes an iterable of [TextInsert] and returns a list of [MentionBlockData].
  /// This is used to extract mentions from a list of text inserts, of a certain type.
  List<MentionBlockData> getMentionBlockData(
    String type,
    Node node,
    Iterable<TextInsert> textInserts,
  ) {
    // Additions contain all the text inserts that were added in this
    // transaction, we only care about the ones that fit the handlers type.

    // Filter out the text inserts where the attribute for the handler type is present.
    final relevantTextInserts =
        textInserts.where((ti) => ti.attributes?[type] != null);

    // Map it to a list of MentionBlockData.
    final mentionBlockDatas = relevantTextInserts.map<MentionBlockData>((ti) {
      // For some text inserts (mostly additions), we might need to modify them after the transaction,
      // so we pass the index of the delta to the handler.
      final index = node.delta?.toList().indexOf(ti) ?? -1;
      return (node, ti.attributes![type], index);
    }).toList();

    return mentionBlockDatas;
  }

  List<MentionBlockData> extractMentionsForType(
    Node node,
    String mentionType, [
    bool includeIndex = true,
  ]) {
    final changes = <MentionBlockData>[];

    final nodesWithDelta = collectMatchingNodes(
      node,
      mentionType,
      livesInDelta: true,
    );

    for (final paragraphNode in nodesWithDelta) {
      final textInserts = paragraphNode.attributes[blockComponentDelta];
      if (textInserts == null || textInserts is! List || textInserts.isEmpty) {
        continue;
      }

      for (final (index, textInsert) in textInserts.indexed) {
        if (textInsert['attributes'] != null &&
            textInsert['attributes'][mentionType] != null) {
          changes.add(
            (
              paragraphNode,
              textInsert['attributes'][mentionType],
              includeIndex ? index : -1,
            ),
          );
        }
      }
    }

    return changes;
  }

  (Iterable<TextInsert>, Iterable<TextInsert>) diffDeltas(
    Delta before,
    Delta after,
  ) {
    final diff = before.diff(after);
    final inverted = diff.invert(before);
    final del = inverted.whereType<TextInsert>();
    final add = diff.whereType<TextInsert>();

    return (add, del);
  }
}
