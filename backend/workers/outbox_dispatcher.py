import asyncio

from app.core.logging import setup_logging
from app.messaging import outbox


def main() -> None:
    setup_logging()
    try:
        asyncio.run(outbox.run_dispatcher())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
