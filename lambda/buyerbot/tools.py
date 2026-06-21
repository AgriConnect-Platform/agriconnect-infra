import urllib.request
import urllib.parse
import json
import os


def _fetch(path, token=None):
    alb_url = os.environ.get('ALB_URL', '')
    url = f"http://{alb_url}{path}"
    print(f"[tools] _fetch → {url}")
    req = urllib.request.Request(url)
    if token:
        req.add_header('Authorization', f'Bearer {token}')
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            raw = resp.read().decode()
            print(f"[tools] _fetch ← status={resp.status} len={len(raw)}")
            return json.loads(raw)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors='ignore')[:200]
        print(f"[tools] _fetch HTTPError {e.code}: {body}")
        return {"error": f"HTTP {e.code}", "detail": body}
    except urllib.error.URLError as e:
        print(f"[tools] _fetch URLError: {e.reason}")
        return {"error": f"Connection failed: {e.reason}"}
    except json.JSONDecodeError as e:
        print(f"[tools] _fetch JSON decode error: {e}")
        return {"error": "Non-JSON response from server"}
    except Exception as e:
        print(f"[tools] _fetch unexpected error: {type(e).__name__}: {e}")
        return {"error": str(e)}


def search_listings(search=None, category=None, max_price=None, limit=10):
    params = {"limit": min(int(limit or 10), 50)}
    if search:
        params["search"] = search
    if category:
        params["category"] = category

    qs = urllib.parse.urlencode(params)
    data = _fetch(f"/api/marketplace/listings?{qs}")

    if isinstance(data, dict) and "error" in data:
        return {"error": "Marketplace unavailable", "detail": data.get("error")}

    listings = data.get("listings", data) if isinstance(data, dict) else data
    if not isinstance(listings, list):
        return {"error": "Unexpected response format", "raw": str(data)[:200]}

    if max_price is not None:
        listings = [l for l in listings if float(l.get("price", 0)) <= float(max_price)]

    simplified = []
    for l in listings[:int(limit)]:
        farmer = l.get("Farmer") or {}
        simplified.append({
            "id": l.get("id"),
            "product": l.get("product_name"),
            "category": l.get("category"),
            "price": float(l.get("price", 0)),
            "unit": l.get("unit"),
            "price_display": f"₹{l.get('price')}/{l.get('unit')}",
            "quantity_available": f"{l.get('quantity')} {l.get('unit')}",
            "farm_name": farmer.get("farm_name"),
            "location": farmer.get("location"),
            "harvest_date": l.get("harvest_date"),
        })

    return {
        "total_found": len(listings),
        "showing": len(simplified),
        "listings": simplified,
    }


def get_price_stats(product_name):
    qs = urllib.parse.urlencode({"search": product_name, "limit": 100})
    data = _fetch(f"/api/marketplace/listings?{qs}")

    if isinstance(data, dict) and "error" in data:
        return {"available": False, "message": f"Could not fetch price data: {data.get('error')}"}

    listings = data.get("listings", data) if isinstance(data, dict) else data
    if not isinstance(listings, list) or len(listings) == 0:
        return {"available": False, "message": f"'{product_name}' is not currently listed in the marketplace."}

    prices = []
    for l in listings:
        try:
            prices.append(float(l["price"]))
        except (KeyError, ValueError, TypeError):
            pass

    if not prices:
        return {"available": False, "message": "Could not parse prices from listings."}

    unit = listings[0].get("unit", "kg")
    avg = sum(prices) / len(prices)
    return {
        "product": product_name,
        "available": True,
        "listings_count": len(prices),
        "min_price": round(min(prices), 2),
        "max_price": round(max(prices), 2),
        "avg_price": round(avg, 2),
        "unit": unit,
        "summary": f"₹{min(prices):.0f}–₹{max(prices):.0f} per {unit} (avg ₹{avg:.0f})",
    }


def get_listing_bids(listing_id, token=None):
    data = _fetch(f"/api/marketplace/bids/{int(listing_id)}", token=token)

    if isinstance(data, dict) and "error" in data:
        return {"error": data.get("error"), "note": "Bids require login — token may be missing or expired"}

    bids = data if isinstance(data, list) else data.get("bids", [])
    if not bids:
        return {
            "listing_id": listing_id,
            "bids_count": 0,
            "message": "No bids placed yet on this listing. You can start with any reasonable amount.",
        }

    amounts = [float(b.get("amount", 0)) for b in bids if b.get("amount")]
    pending = [b for b in bids if b.get("status") == "PENDING"]
    highest = max(amounts) if amounts else 0

    return {
        "listing_id": listing_id,
        "total_bids": len(bids),
        "pending_bids": len(pending),
        "highest_bid": f"₹{highest:.0f}",
        "lowest_bid": f"₹{min(amounts):.0f}" if amounts else "N/A",
        "avg_bid": f"₹{sum(amounts)/len(amounts):.0f}" if amounts else "N/A",
        "competitive_suggestion": f"To win, bid above ₹{highest:.0f}" if highest > 0 else "No competition yet — any amount works.",
    }


def get_available_categories():
    data = _fetch("/api/marketplace/categories")
    if isinstance(data, dict) and "error" in data:
        return {"error": "Could not fetch categories", "detail": data.get("error")}
    categories = data if isinstance(data, list) else []
    return {"categories": categories, "count": len(categories)}
