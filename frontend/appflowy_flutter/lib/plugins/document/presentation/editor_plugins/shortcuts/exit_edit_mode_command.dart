import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// End key event.
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent customExitEditingCommand = CommandShortcutEvent(
  key: 'exit the editing mode',
  getDescription: () => AppFlowyEditorL10n.current.cmdExitEditing,
  command: 'escape',
  handler: _exitEditingCommandHandler,
);

CommandShortcutEventHandler _exitEditingCommandHandler = (editorState) {
  /*
  if (editorState.selection == null) {
    return KeyEventResult.ignored;
  }
  editorState.selection = null;
  editorState.service.keyboardService?.closeKeyboard();
  return KeyEventResult.handled;
  */
  print('is vim mode on? ${editorState.vimMode}');
  if (editorState.vimMode == true &&
      editorState.editable == true &&
      editorState.mode == VimModes.insertMode) {
    if (editorState.mode == VimModes.normalMode) {
      print('already in normal mode already!');
      return KeyEventResult.ignored;
    }
    editorState.prevSelection = editorState.selection;
    editorState.selection = null;
    editorState.mode = VimModes.normalMode;
    editorState.editable = false;
    editorState.selection = editorState.prevSelection;
    editorState.service.keyboardService?.closeKeyboard();
    print('dropping into normal mode');
    return KeyEventResult.handled;
  }
  editorState.selection = null;
  editorState.service.keyboardService?.closeKeyboard();
  return KeyEventResult.handled;
};
