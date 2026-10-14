import aio_pika
from aio_pika.abc import AbstractChannel

from app.domain.events import (
    EXCHANGE_NAME,
    QUARANTINE_EXCHANGE,
    QUARANTINE_QUEUE,
    QUARANTINE_ROUTING_KEY,
    WORKER_BINDINGS,
)


async def declare_topology(channel: AbstractChannel) -> None:
    exchange = await channel.declare_exchange(
        EXCHANGE_NAME, aio_pika.ExchangeType.TOPIC, durable=True
    )
    quarantine_exchange = await channel.declare_exchange(
        QUARANTINE_EXCHANGE, aio_pika.ExchangeType.TOPIC, durable=True
    )
    quarantine_queue = await channel.declare_queue(QUARANTINE_QUEUE, durable=True)
    await quarantine_queue.bind(quarantine_exchange, routing_key=QUARANTINE_ROUTING_KEY)

    for queue_name, _pattern, routing_key in WORKER_BINDINGS:
        queue = await channel.declare_queue(queue_name, durable=True)
        await queue.bind(exchange, routing_key=routing_key)
