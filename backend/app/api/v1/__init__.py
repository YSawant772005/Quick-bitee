from fastapi import APIRouter

from app.api.v1 import admin, auth, notifications, orders, promotions, restaurants

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(restaurants.router)
api_router.include_router(promotions.router)
api_router.include_router(orders.router)
api_router.include_router(notifications.router)
api_router.include_router(admin.router)
