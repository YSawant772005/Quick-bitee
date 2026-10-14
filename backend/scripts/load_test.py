"""100-order load benchmark.

Places N orders concurrently (unique Idempotency-Key per order), then polls
until every order reaches a terminal status. Prints wall time and the final
status distribution.

Usage:
    python scripts/load_test.py --api http://localhost:8000 --orders 100 --concurrency 10
"""

import argparse
import asyncio
import statistics
import time
import uuid

import httpx

TERMINAL = {"DRIVER_ASSIGNED", "PAYMENT_FAILED", "FAILED"}


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--api", default="http://localhost:8000")
    parser.add_argument("--orders", type=int, default=100)
    parser.add_argument("--concurrency", type=int, default=10)
    parser.add_argument("--email", default="customer@quickbite.dev")
    parser.add_argument("--password", default="Customer#123")
    args = parser.parse_args()
    base = f"{args.api}/api/v1"

    async with httpx.AsyncClient(base_url=base, timeout=30) as client:
        token = (
            await client.post(
                "/auth/login", json={"email": args.email, "password": args.password}
            )
        ).json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        catalog = (await client.get("/restaurants", headers=headers)).json()
        restaurant = catalog["items"][0]
        menu = (
            await client.get(f"/restaurants/{restaurant['id']}/menu", headers=headers)
        ).json()
        items = [{"menu_item_id": menu["items"][0]["id"], "quantity": 2}]

        sem = asyncio.Semaphore(args.concurrency)
        latencies: list[float] = []
        failures: list[str] = []
        lock = asyncio.Lock()

        async def place() -> None:
            async with sem:
                start = time.perf_counter()
                try:
                    resp = await client.post(
                        "/orders",
                        json={
                            "restaurant_id": restaurant["id"],
                            "delivery_address": "Load Test Boulevard 100",
                            "items": items,
                        },
                        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
                    )
                    if resp.status_code != 202:
                        async with lock:
                            failures.append(f"{resp.status_code}: {resp.text[:200]}")
                finally:
                    async with lock:
                        latencies.append(time.perf_counter() - start)

        t0 = time.perf_counter()
        await asyncio.gather(*[place() for _ in range(args.orders)])
        place_wall = time.perf_counter() - t0

        # poll until all terminal
        deadline = time.perf_counter() + 300
        while time.perf_counter() < deadline:
            summary = (await client.get("/admin/summary", headers=headers))
            if summary.status_code != 200:
                admin_login = (
                    await client.post(
                        "/auth/login",
                        json={"email": "admin@quickbite.dev", "password": "Admin#123"},
                    )
                ).json()["access_token"]
                summary = await client.get(
                    "/admin/summary", headers={"Authorization": f"Bearer {admin_login}"}
                )
            body = summary.json()
            done = sum(
                body["by_status"].get(s, 0) for s in TERMINAL
            )
            non_terminal = body["total_orders"] - done
            if non_terminal == 0 and body["total_orders"] >= args.orders:
                break
            await asyncio.sleep(2)
        pipeline_wall = time.perf_counter() - t0

        final_summary = summary.json()
        print(f"orders submitted       : {args.orders}")
        print(f"submit failures        : {len(failures)}")
        for f in failures[:5]:
            print(f"  {f}")
        print(f"submit wall time       : {place_wall:.1f}s")
        print(f"checkout p50 latency   : {statistics.median(latencies)*1000:.0f}ms")
        print(f"checkout p95 latency   : {sorted(latencies)[int(len(latencies)*0.95)]*1000:.0f}ms")
        print(f"full pipeline wall     : {pipeline_wall:.1f}s")
        print(f"throughput             : {args.orders/max(pipeline_wall,0.001):.1f} orders/s")
        print(f"status distribution    : {final_summary['by_status']}")
        print(f"pending outbox         : {final_summary['pending_outbox']}")
        print(f"retry backlog          : {final_summary['retry_backlog']}")
        print(f"quarantined            : {final_summary['quarantine_count']}")


if __name__ == "__main__":
    asyncio.run(main())
