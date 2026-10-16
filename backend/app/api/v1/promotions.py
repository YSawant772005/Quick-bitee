from fastapi import APIRouter, Depends

from app import promotions
from app.api.dependencies import get_current_user
from app.models.users import User
from app.schemas.catalog import OfferOut, PromoBannerOut, PromotionsOut

router = APIRouter(tags=["promotions"])


@router.get("/promotions", response_model=PromotionsOut)
async def get_promotions(
    current_user: User = Depends(get_current_user),
) -> PromotionsOut:
    """Homepage banners and offers in one payload.

    Empty in production: the demo promotions behind this endpoint are only
    served outside production and always carry ``is_demo``/``badge`` so the
    client can label them honestly.
    """
    return PromotionsOut(
        banners=[
            PromoBannerOut.model_validate(b) for b in promotions.demo_banners()
        ],
        offers=[OfferOut.model_validate(o) for o in promotions.demo_offers()],
    )
