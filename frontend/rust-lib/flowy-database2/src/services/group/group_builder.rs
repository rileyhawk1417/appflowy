use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use collab_database::fields::Field;
use collab_database::rows::{Cell, Row, RowId};
use flowy_error::FlowyResult;

use crate::entities::FieldType;
use crate::services::field::TypeOption;
use crate::services::group::{
  CheckboxGroupController, CheckboxGroupControllerContext, DateGroupController,
  DateGroupControllerContext, DefaultGroupController, Group, GroupContextDelegate, GroupController,
  GroupControllerDelegate, GroupSetting, MultiSelectGroupController,
  MultiSelectGroupControllerContext, SingleSelectGroupController,
  SingleSelectGroupControllerContext, URLGroupController, URLGroupControllerContext,
};

/// The [GroupsBuilder] trait is used to generate the groups for different [FieldType]
#[async_trait]
pub trait GroupsBuilder: Send + Sync + 'static {
  type Context;
  type GroupTypeOption: TypeOption;

  async fn build(
    field: &Field,
    context: &Self::Context,
    type_option: &Self::GroupTypeOption,
  ) -> GeneratedGroups;
}

pub struct GeneratedGroups {
  pub no_status_group: Option<Group>,
  pub groups: Vec<Group>,
}

pub struct MoveGroupRowContext<'a> {
  pub row: &'a Row,
  pub updated_cells: &'a mut UpdatedCells,
  pub field: &'a Field,
  pub to_group_id: &'a str,
  pub to_row_id: Option<RowId>,
}

/// A map of the updated cells.
/// The key is the field id, the value is the updated cell.
pub type UpdatedCells = HashMap<String, Cell>;

/// Returns a group controller.
///
/// Each view can be grouped by one field, each field has its own group controller.  
/// # Arguments
///
/// * `view_id`: the id of the view
/// * `grouping_field_rev`: the grouping field
/// * `row_revs`: the rows will be separated into different groups
/// * `configuration_reader`: a reader used to read the group configuration from disk
/// * `configuration_writer`: as writer used to write the group configuration to disk
///
#[tracing::instrument(
  level = "trace",
  skip_all,
  fields(grouping_field_id=%grouping_field.id, grouping_field_type)
  err
)]
pub(crate) async fn make_group_controller<D>(
  view_id: &str,
  grouping_field: Field,
  delegate: D,
) -> FlowyResult<Box<dyn GroupController>>
where
  D: GroupContextDelegate + GroupControllerDelegate,
{
  let grouping_field_type = FieldType::from(grouping_field.field_type);
  tracing::Span::current().record("grouping_field", grouping_field_type.default_name());

  let group_controller: Box<dyn GroupController>;
  let delegate = Arc::new(delegate);

  match grouping_field_type {
    FieldType::SingleSelect => {
      let configuration = SingleSelectGroupControllerContext::new(
        view_id.to_string(),
        grouping_field.clone(),
        delegate.clone(),
      )
      .await?;
      let controller =
        SingleSelectGroupController::new(&grouping_field, configuration, delegate.clone()).await?;
      group_controller = Box::new(controller);
    },
    FieldType::MultiSelect => {
      let configuration = MultiSelectGroupControllerContext::new(
        view_id.to_string(),
        grouping_field.clone(),
        delegate.clone(),
      )
      .await?;
      let controller =
        MultiSelectGroupController::new(&grouping_field, configuration, delegate.clone()).await?;
      group_controller = Box::new(controller);
    },
    FieldType::Checkbox => {
      let configuration = CheckboxGroupControllerContext::new(
        view_id.to_string(),
        grouping_field.clone(),
        delegate.clone(),
      )
      .await?;
      let controller =
        CheckboxGroupController::new(&grouping_field, configuration, delegate.clone()).await?;
      group_controller = Box::new(controller);
    },
    FieldType::URL => {
      let configuration = URLGroupControllerContext::new(
        view_id.to_string(),
        grouping_field.clone(),
        delegate.clone(),
      )
      .await?;
      let controller =
        URLGroupController::new(&grouping_field, configuration, delegate.clone()).await?;
      group_controller = Box::new(controller);
    },
    FieldType::DateTime => {
      let configuration = DateGroupControllerContext::new(
        view_id.to_string(),
        grouping_field.clone(),
        delegate.clone(),
      )
      .await?;
      let controller =
        DateGroupController::new(&grouping_field, configuration, delegate.clone()).await?;
      group_controller = Box::new(controller);
    },
    _ => {
      group_controller = Box::new(DefaultGroupController::new(
        view_id,
        &grouping_field,
        delegate.clone(),
      ));
    },
  }

  #[cfg(feature = "verbose_log")]
  {
    for group in group_controller.get_all_groups() {
      tracing::trace!("[Database]: group: {}", group);
    }
  }
  Ok(group_controller)
}

/// Returns a `default` group configuration for the [Field]
///
/// # Arguments
///
/// * `field`: making the group configuration for the field
///
pub fn default_group_setting(field: &Field) -> GroupSetting {
  let field_id = field.id.clone();
  GroupSetting::new(field_id, field.field_type, "".to_owned())
}

pub fn make_no_status_group(field: &Field) -> Group {
  Group {
    id: field.id.clone(),
    visible: true,
  }
}
