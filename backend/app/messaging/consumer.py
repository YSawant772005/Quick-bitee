import asyncio
import contextlib

import aio_pika
from aio_pika.abc import AbstractIncomingMessage

from app.core.config import settings
from app.core.errors import InvalidRequestError
from app.core.logging import get_logger
from app.domain.events import EventEnvelope, parse_envelope
from app.messaging.connection import get_connection
from app.messaging.retries import ProcessFailure, quarantine_event, schedule_retry
from app.messaging.topology import declare_topology

logger = get_logger(__name__)


class EventConsumer:
    """Base consumer: manual acks, bounded prefetch, dedupe + lock + transition core
    delegated to the handler, durable retry scheduling on known failures, quarantine
    on malformed events."""

    def __init__(self, consumer_name: str, queue_name: str, handler, prefetch: int = 1):
        self.consumer_name = consumer_name
        self.queue_name = queue_name
        self.handler = handler  # async fn(envelope: EventEnvelope, attempt: int) -> None
        self.prefetch = prefetch

    async def run(self) -> None:
        connection = await get_connection()
        channel = await connection.channel()
        await channel.set_qos(prefetch_count=self.prefetch)
        await declare_topology(channel)
        queue = await channel.declare_queue(self.queue_name, durable=True)
        await queue.consume(self._on_message, no_ack=False)
        logger.info("consumer started", extra={"consumer": self.consumer_name})
        while True:
            await asyncio.sleep(3600)

    async def _on_message(self, message: AbstractIncomingMessage) -> None:
        try:
            envelope = parse_envelope(message.body)
        except InvalidRequestError as exc:
            logger.warning("malformed event quarantined", extra={"consumer": self.consumer_name})
            await quarantine_event(
                consumer_name=self.consumer_name,
                event_id="unknown",
                queue_name=self.queue_name,
                reason="malformed_envelope",
                raw_payload=message.body.decode("utf-8", "ignore")[:4000],
            )
            with contextlib.suppress(Exception):
                await message.ack()
            return

        attempt = 1
        raw_attempt = (message.headers or {}).get("x_attempt")
        if isinstance(raw_attempt, int) and raw_attempt >= 1:
            attempt = raw_attempt

        try:
            await self.handler(envelope, attempt)
        except ProcessFailure as exc:
            logger.warning(
                "processing failed",
                extra={"consumer": self.consumer_name, "event_id": envelope.event_id, "extra": str(exc)},
            )
            try:
                await schedule_retry(
                    self.consumer_name, envelope, self.queue_name, attempt, settings.retry_delays
                )
            except Exception:
                logger.exception("retry scheduling failed; preserving original message")
                with contextlib.suppress(Exception):
                    await message.nack(requeue=True)
                return
            with contextlib.suppress(Exception):
                await message.ack()
            return
        except Exception:
            logger.exception(
                "unhandled processing error; quarantining",
                extra={"consumer": self.consumer_name, "event_id": envelope.event_id},
            )
            await quarantine_event(
                consumer_name=self.consumer_name,
                event_id=envelope.event_id,
                queue_name=self.queue_name,
                reason="unhandled_exception",
                envelope=envelope.to_dict(),
            )
            with contextlib.suppress(Exception):
                await message.ack()
            return

        with contextlib.suppress(Exception):
            await message.ack()
