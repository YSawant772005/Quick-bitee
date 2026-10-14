"""End-to-end demo: sign in, browse, place an order, poll until terminal state.

Usage:
  python -m scripts.demo_order [--base http://127.0.0.1:8000] [--idem-key demo-1]
          [--wait 90] [--expect-status DRIVER_ASSIGNED]
"""
import argparse
import asyncio
import uuid

import httpx

from app.domain import order_state_machine as sm


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8000")
    parser.add_argument("--email", default="customer@quickbite.dev")
    parser.add_argument("--password", default="Customer#123")
    parser.add_argument("--idem-key", default=None)
    parser.add_argument("--wait", type=float, default=90.0)
    parser.add_argument("--expect-status", default=None)
    parser.add_argument("--admin", action="store_true")
    args = parser.parse_args()

    async with httpx.AsyncClient(base_url=args.base, timeout=10.0) as client:
        login = await client.post(
            "/api/v1/auth/login",
            json={"email": args.email, "password": args.password},
        )
        login.raise_for_status()
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}
        print(f"signed in as {args.email}")

        restaurants = (
            await client.get("/api/v1/restaurants", headers=headers, params={"page_size": 1})
        ).json()
        restaurant = restaurants["items"][0]
        menu = (
            await client.get(
                f"/api/v1/restaurants/{restaurant['id']}/menu",
                headers=headers,
                params={"page_size": 2},
            )
        ).json()
        items = [{"menu_item_id": i["id"], "quantity": 2} for i in menu["items"]]
        print(f"ordering from {restaurant['name']}: {[i['menu_item_id'][:8] for i in items]}")

        idem_key = args.idem_key or str(uuid.uuid4())
        accepted = await client.post(
            "/api/v1/orders",
            headers={**headers, "Idempotency-Key": idem_key},
            json={
                "restaurant_id": restaurant["id"],
                "delivery_address": "12 Lake Road, Bengaluru 560001",
                "items": items,
            },
        )
        print(f"checkout HTTP {accepted.status_code}: {accepted.text[:200]}")
        accepted.raise_for_status()
        order_id = accepted.json()["order_id"]
        print(f"order {order_id} accepted, waiting for processing...")

        deadline = asyncio.get_event_loop().time() + args.wait
        last_status = None
        while asyncio.get_event_loop().time() < deadline:
            detail = (await client.get(f"/api/v1/orders/{order_id}", headers=headers)).json()
            if detail["status"] != last_status:
                print(f"  -> {detail['status']} (version {detail['version']})")
                last_status = detail["status"]
            if sm.is_terminal(detail["status"]):
                break
            await asyncio.sleep(2.0)

        history = (
            await client.get(f"/api/v1/orders/{order_id}/history", headers=headers)
        ).json()
        print("timeline:", [(h["status"], h["version"]) for h in history["items"]])
        notifications = (
            await client.get(f"/api/v1/orders/{order_id}/notifications", headers=headers)
        ).json()
        print("notifications:", [n["event_type"] for n in notifications["items"]])

        if args.admin:
            admin_login = await client.post(
                "/api/v1/auth/login",
                json={"email": "admin@quickbite.dev", "password": "Admin#123"},
            )
            admin_headers = {"Authorization": f"Bearer {admin_login.json()['access_token']}"}
            summary = (await client.get("/api/v1/admin/summary", headers=admin_headers)).json()
            print("admin summary:", summary)

        if args.expect_status and last_status != args.expect_status:
            raise SystemExit(f"FAIL: expected {args.expect_status}, got {last_status}")
        print(f"FINAL STATUS: {last_status}")


if __name__ == "__main__":
    asyncio.run(main())
