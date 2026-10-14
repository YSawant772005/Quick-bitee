STATUS_PENDING = "PENDING"
STATUS_PAID = "PAID"
STATUS_CONFIRMED = "CONFIRMED"
STATUS_DRIVER_ASSIGNED = "DRIVER_ASSIGNED"
STATUS_PAYMENT_FAILED = "PAYMENT_FAILED"
STATUS_FAILED = "FAILED"

TERMINAL_STATUSES = {STATUS_PAYMENT_FAILED, STATUS_FAILED, STATUS_DRIVER_ASSIGNED}

# source status -> allowed target statuses
ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    STATUS_PENDING: {STATUS_PAID, STATUS_PAYMENT_FAILED},
    STATUS_PAID: {STATUS_CONFIRMED, STATUS_FAILED},
    STATUS_CONFIRMED: {STATUS_DRIVER_ASSIGNED, STATUS_FAILED},
}


def is_terminal(status: str) -> bool:
    return status in TERMINAL_STATUSES


def can_transition(from_status: str, to_status: str) -> bool:
    return to_status in ALLOWED_TRANSITIONS.get(from_status, set())


def assert_transition(from_status: str, to_status: str) -> None:
    from app.core.errors import ConflictError

    if not can_transition(from_status, to_status):
        raise ConflictError(
            f"Transition from {from_status} to {to_status} is not allowed.",
            {"from_status": from_status, "to_status": to_status},
        )
