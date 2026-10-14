from typing import Any


class AppError(Exception):
    status_code = 500
    code = "INTERNAL_ERROR"

    def __init__(self, message: str, details: dict[str, Any] | None = None):
        super().__init__(message)
        self.message = message
        self.details = details or {}


class UnauthorizedError(AppError):
    status_code = 401
    code = "UNAUTHENTICATED"


class ForbiddenError(AppError):
    status_code = 403
    code = "FORBIDDEN"


class NotFoundError(AppError):
    status_code = 404
    code = "NOT_FOUND"


class ConflictError(AppError):
    status_code = 409
    code = "CONFLICT"


class InvalidRequestError(AppError):
    status_code = 422
    code = "INVALID_REQUEST"


ERROR_MESSAGES = {
    "UNAUTHENTICATED": "Missing, invalid or expired authentication.",
    "FORBIDDEN": "You do not have permission to access this resource.",
    "NOT_FOUND": "The requested resource was not found.",
    "CONFLICT": "The request conflicts with existing state.",
    "INVALID_REQUEST": "The request could not be processed.",
    "INTERNAL_ERROR": "An unexpected error occurred.",
}
