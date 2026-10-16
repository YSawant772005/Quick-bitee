from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str = "postgresql+asyncpg://quickbite:quickbite@localhost:5432/quickbite"
    AMQP_URL: str = "amqp://quickbite:quickbite@localhost:5672/"

    JWT_SECRET: str = "dev-insecure-secret-change-me"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    CORS_ORIGINS: str = "http://localhost:8088,http://127.0.0.1:8088"
    PAGE_SIZE_MAX: int = 100
    PAGE_SIZE_DEFAULT: int = 20

    SIM_PAYMENT_DELAY_SECONDS: float = 0.4
    SIM_RESTAURANT_DELAY_SECONDS: float = 0.6
    SIM_DELIVERY_DELAY_SECONDS: float = 0.6
    SIM_NOTIFICATION_DELAY_SECONDS: float = 0.05

    PAYMENT_FAILURE_MODE: str = "none"  # none | twice_then_succeed | always_fail
    RESTAURANT_FAILURE_MODE: str = "none"  # none | always_fail
    DELIVERY_FAILURE_MODE: str = "none"  # none | always_fail
    NOTIFICATION_FAILURE_MODE: str = "none"  # none | always_fail
    WORKER_CRASH_POINT: str = "none"  # none | before_tx | after_tx

    RETRY_DELAYS_SECONDS: str = "2,10,30"
    OUTBOX_POLL_INTERVAL_SECONDS: float = 0.5
    OUTBOX_BATCH_SIZE: int = 50
    RETRY_SCHEDULER_INTERVAL_SECONDS: float = 1.0

    LOG_LEVEL: str = "INFO"

    #: Deployment environment. Demo promotions are only exposed outside production.
    APP_ENV: str = "development"
    #: Explicit override for the clearly-labelled demo banners/offers.
    #: "true"/"false"; empty means "default on unless APP_ENV=production".
    DEMO_PROMOTIONS_ENABLED: str = ""

    @property
    def is_production(self) -> bool:
        return self.APP_ENV.strip().lower() == "production"

    @property
    def demo_promotions_enabled(self) -> bool:
        flag = self.DEMO_PROMOTIONS_ENABLED.strip().lower()
        if flag in {"1", "true", "yes", "on"}:
            return True
        if flag in {"0", "false", "no", "off"}:
            return False
        return not self.is_production

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]

    @property
    def retry_delays(self) -> list[float]:
        return [float(x) for x in self.RETRY_DELAYS_SECONDS.split(",") if x.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
