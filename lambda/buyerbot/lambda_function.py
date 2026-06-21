import json
import boto3
import os
import urllib.request
import urllib.error

bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("BEDROCK_REGION", "us-east-1"))

SYSTEM_PROMPT_BASE = """You are BuyerBot, an expert AI marketplace assistant for AgriConnect buyers in India.

You help buyers:
- Find agricultural produce at the best prices
- Understand market trends and price ranges for Indian commodities
- Make smart bidding decisions
- Discover available product categories and listings
- Compare prices, quality, and availability

Typical Indian wholesale price ranges (for reference when live data is unavailable):
Rice: ₹20-45/kg | Wheat: ₹18-32/kg | Tomatoes: ₹15-60/kg | Potatoes: ₹10-30/kg
Onions: ₹12-50/kg | Mangoes: ₹40-200/kg | Corn: ₹15-25/kg | Cotton: ₹55-75/kg
Sugarcane: ₹3-4/kg | Pulses: ₹50-120/kg | Bananas: ₹20-60/dozen

Always be practical and help buyers get the best value."""


def get_marketplace_listings(token: str, alb_url: str) -> list:
    if not alb_url or not token:
        return []
    try:
        url = f"http://{alb_url}/api/marketplace/listings?limit=20"
        req = urllib.request.Request(
            url,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            if isinstance(data, list):
                return data
            return data.get("listings", data.get("data", []))
    except Exception:
        return []


def lambda_handler(event, context):
    try:
        body    = json.loads(event.get("body", "{}"))
        message = body.get("message", "").strip()
        token   = body.get("token", "")
        history = body.get("history", [])  # [{role:"user"|"assistant", text:"..."}]

        # Fetch live marketplace data
        alb_url  = os.environ.get("ALB_URL", "")
        listings = get_marketplace_listings(token, alb_url)

        # Build system prompt
        system_prompt = SYSTEM_PROMPT_BASE
        if listings:
            system_prompt += f"\n\n=== LIVE MARKETPLACE ({len(listings)} listings) ===\n"
            for item in listings[:15]:
                name  = item.get("title") or item.get("produce_name", "Unknown")
                price = item.get("price_per_unit", item.get("price", "N/A"))
                qty   = item.get("quantity_available", item.get("quantity", "N/A"))
                unit  = item.get("unit", "kg")
                cat   = item.get("category", "")
                farmer = item.get("farmer_name", "")
                line = f"• {name}"
                if cat:
                    line += f" [{cat}]"
                line += f": ₹{price}/{unit}, {qty} {unit} available"
                if farmer:
                    line += f" from {farmer}"
                system_prompt += line + "\n"
            system_prompt += "\nUse this LIVE data when answering questions about availability and prices."
        else:
            system_prompt += "\n\n(Live marketplace data unavailable — using general knowledge for price guidance.)"

        # Build messages with conversation history
        messages = []
        for turn in history:
            role = "user" if turn.get("role") == "user" else "assistant"
            messages.append({"role": role, "content": [{"text": turn.get("text", "")}]})

        messages.append({"role": "user", "content": [{"text": message or "Hello"}]})

        response = bedrock.converse(
            modelId=os.environ.get("MODEL_ID", "amazon.nova-lite-v1:0"),
            messages=messages,
            system=[{"text": system_prompt}],
            inferenceConfig={"maxTokens": 1024, "temperature": 0.7}
        )

        reply = response["output"]["message"]["content"][0]["text"]

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({"response": reply})
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"response": "I'm having trouble right now. Please try again in a moment."})
        }
