import json

import aio_pika
from aio_pika.abc import AbstractChannel, AbstractExchange
from aio_pika.exceptions import DeliveryError
from aio_pika.message import DeliveryMode, Message

from app.core.logging import get_logger
from app.domain.events import EXCHANGE_NAME
from app.messaging.connection import get_connection

logger = get_logger(__name__)


class PublishError(Exception):
    pass


async def get_publisher_channel() -> AbstractChannel:
    connection = await get_connection()
    return await connection.channel(publisher_confirms=True)


async def get_exchange(channel: AbstractChannel) -> AbstractExchange:
    return await channel.declare_exchange(EXCHANGE_NAME, aio_pika.ExchangeType.TOPIC, durable=True)


async def publish_event(
    channel: AbstractChannel, routing_key: str, payload: dict, correlation_id: str
) -> None:
    exchange = await get_exchange(channel)
    message = Message(
        body=json.dumps(payload).encode("utf-8"),
        content_type="application/json",
        delivery_mode=DeliveryMode.PERSISTENT,
        correlation_id=correlation_id,
    )
    try:
        await exchange.publish(message, routing_key=routing_key, mandatory=True)
    except DeliveryError as exc:
        logger.error("unroutable message", extra={"routing_key": routing_key})
        raise PublishError(f"Message unroutable for key {routing_key}") from exc
    except Exception as exc:
        logger.error("publish failed", extra={"routing_key": routing_key})
        raise PublishError(str(exc)) from exc


async def publish_to_queue(
    channel: AbstractChannel, queue_name: str, payload: dict, correlation_id: str, headers: dict | None = None
) -> None:
    queue = await channel.declare_queue(queue_name, durable=True)
    message = Message(
        body=json.dumps(payload).encode("utf-8"),
        content_type="application/json",
        delivery_mode=DeliveryMode.PERSISTENT,
        correlation_id=correlation_id,
        headers=headers or {},
    )
    await queue.channel.default_exchange.publish(message, routing_key=queue_name, mandatory=True)
