import contextlib
import uuid
from contextvars import ContextVar

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.api.v1 import api_router
from app.core.config import settings
from app.core.errors import ERROR_MESSAGES, AppError
from app.core.logging import get_logger, setup_logging
from app.db.session import engine

setup_logging()
logger = get_logger(__name__)

request_id_var: ContextVar[str] = ContextVar("request_id", default="")


class RequestIdFilter:
    def filter(self, record):
        record.request_id = request_id_var.get()
        return True


import logging

logging.getLogger().handlers[0].addFilter(RequestIdFilter())


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await engine.dispose()


def create_app() -> FastAPI:
    app = FastAPI(title="QuickBite API", version="1.0.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def request_id_middleware(request: Request, call_next):
        request_id_var.set(str(uuid.uuid4()))
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id_var.get()
        return response

    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError):
        request_id = request_id_var.get()
        logger.warning("app error", extra={"request_id": request_id, "extra": exc.message})
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "code": exc.code,
                "message": exc.message,
                "details": exc.details,
                "request_id": request_id,
            },
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError):
        request_id = request_id_var.get()
        return JSONResponse(
            status_code=422,
            content={
                "code": "INVALID_REQUEST",
                "message": ERROR_MESSAGES["INVALID_REQUEST"],
                "details": {"errors": exc.errors()},
                "request_id": request_id,
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_error_handler(request: Request, exc: Exception):
        request_id = request_id_var.get()
        logger.exception("unhandled error", extra={"request_id": request_id})
        return JSONResponse(
            status_code=500,
            content={
                "code": "INTERNAL_ERROR",
                "message": ERROR_MESSAGES["INTERNAL_ERROR"],
                "details": {},
                "request_id": request_id,
            },
        )

    app.include_router(api_router)

    @app.get("/health/live")
    async def health_live():
        return {"status": "ok"}

    @app.get("/health/ready")
    async def health_ready():
        problems: list[str] = []
        try:
            async with engine.connect() as conn:
                await conn.exec_driver_sql("SELECT 1")
        except Exception:
            problems.append("database")
        try:
            import aio_pika

            conn = await asyncio_wait_for(aio_pika.connect(settings.AMQP_URL), timeout=3)
            await conn.close()
        except Exception:
            problems.append("amqp")
        if problems:
            return JSONResponse(status_code=503, content={"status": "not_ready", "problems": problems})
        return {"status": "ready"}

    static_dir = __import__("pathlib").Path(__file__).parent / "static"
    static_dir.mkdir(exist_ok=True)
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")
    return app


async def asyncio_wait_for(coro, timeout):
    import asyncio

    return await asyncio.wait_for(coro, timeout=timeout)


app = create_app()
