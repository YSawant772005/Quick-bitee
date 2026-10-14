import aio_pika
from aio_pika.abc import AbstractRobustConnection

from app.core.config import settings

_connection: AbstractRobustConnection | None = None


async def get_connection() -> AbstractRobustConnection:
    global _connection
    if _connection is None or _connection.is_closed:
        _connection = await aio_pika.connect_robust(settings.AMQP_URL)
    return _connection


async def close_connection() -> None:
    global _connection
    if _connection and not _connection.is_closed:
        await _connection.close()
    _connection = None
