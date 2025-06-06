use crate::{ErrorCode, FlowyError};
use client_api::error::{AppResponseError, ErrorCode as AppErrorCode};

impl From<AppResponseError> for FlowyError {
  fn from(error: AppResponseError) -> Self {
    let code = match error.code {
      AppErrorCode::Ok => ErrorCode::Internal,
      AppErrorCode::Unhandled => ErrorCode::Internal,
      AppErrorCode::RecordNotFound => ErrorCode::RecordNotFound,
      AppErrorCode::RecordAlreadyExists => ErrorCode::RecordAlreadyExists,
      AppErrorCode::InvalidEmail => ErrorCode::EmailFormatInvalid,
      AppErrorCode::InvalidPassword => ErrorCode::PasswordFormatInvalid,
      AppErrorCode::OAuthError => ErrorCode::UserUnauthorized,
      AppErrorCode::MissingPayload => ErrorCode::MissingPayload,
      AppErrorCode::OpenError => ErrorCode::Internal,
      AppErrorCode::InvalidUrl => ErrorCode::InvalidURL,
      AppErrorCode::InvalidRequest => ErrorCode::InvalidRequest,
      AppErrorCode::InvalidOAuthProvider => ErrorCode::InvalidAuthConfig,
      AppErrorCode::NotLoggedIn => ErrorCode::UserUnauthorized,
      AppErrorCode::NotEnoughPermissions => ErrorCode::NotEnoughPermissions,
      AppErrorCode::NetworkError => ErrorCode::NetworkError,
      AppErrorCode::RequestTimeout => ErrorCode::RequestTimeout,
      AppErrorCode::PayloadTooLarge => ErrorCode::PayloadTooLarge,
      AppErrorCode::UserUnAuthorized => ErrorCode::UserUnauthorized,
      AppErrorCode::WorkspaceLimitExceeded => ErrorCode::WorkspaceLimitExceeded,
      AppErrorCode::WorkspaceMemberLimitExceeded => ErrorCode::WorkspaceMemberLimitExceeded,
      AppErrorCode::AIResponseLimitExceeded => ErrorCode::AIResponseLimitExceeded,
      AppErrorCode::AIImageResponseLimitExceeded => ErrorCode::AIImageResponseLimitExceeded,
      AppErrorCode::AIMaxRequired => ErrorCode::AIMaxRequired,
      AppErrorCode::FileStorageLimitExceeded => ErrorCode::FileStorageLimitExceeded,
      AppErrorCode::SingleUploadLimitExceeded => ErrorCode::SingleUploadLimitExceeded,
      AppErrorCode::CustomNamespaceDisabled => ErrorCode::CustomNamespaceRequirePlanUpgrade,
      AppErrorCode::CustomNamespaceDisallowed => ErrorCode::CustomNamespaceNotAllowed,
      AppErrorCode::PublishNamespaceAlreadyTaken => ErrorCode::CustomNamespaceAlreadyTaken,
      AppErrorCode::CustomNamespaceTooShort => ErrorCode::CustomNamespaceTooShort,
      AppErrorCode::CustomNamespaceTooLong => ErrorCode::CustomNamespaceTooLong,
      AppErrorCode::CustomNamespaceReserved => ErrorCode::CustomNamespaceReserved,
      AppErrorCode::PublishNameAlreadyExists => ErrorCode::PublishNameAlreadyExists,
      AppErrorCode::PublishNameInvalidCharacter => ErrorCode::PublishNameInvalidCharacter,
      AppErrorCode::PublishNameTooLong => ErrorCode::PublishNameTooLong,
      AppErrorCode::CustomNamespaceInvalidCharacter => ErrorCode::CustomNamespaceInvalidCharacter,
      AppErrorCode::AIServiceUnavailable => ErrorCode::AIServiceUnavailable,
      AppErrorCode::FreePlanGuestLimitExceeded => ErrorCode::FreePlanGuestLimitExceeded,
      AppErrorCode::InvalidGuest => ErrorCode::InvalidGuest,
      AppErrorCode::PaidPlanGuestLimitExceeded => ErrorCode::PaidPlanGuestLimitExceeded,
      _ => ErrorCode::Internal,
    };

    FlowyError::new(code, error.message)
  }
}
