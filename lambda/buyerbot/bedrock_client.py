import boto3
import json
import os
from system_prompt import SYSTEM_PROMPT
from tools import search_listings, get_price_stats, get_listing_bids, get_available_categories

TOOL_CONFIG = {
    "tools": [
        {
            "toolSpec": {
                "name": "search_listings",
                "description": (
                    "Search real-time produce listings from the marketplace. "
                    "Use this to find products by name, filter by category or maximum price. "
                    "Always call this before making any claims about what is available."
                ),
                "inputSchema": {
                    "json": {
                        "type": "object",
                        "properties": {
                            "search": {
                                "type": "string",
                                "description": "Product name or keyword, e.g. 'tomatoes', 'wheat'"
                            },
                            "category": {
                                "type": "string",
                                "description": "Category filter e.g. Vegetables, Fruits, Grains, Pulses"
                            },
                            "max_price": {
                                "type": "number",
                                "description": "Maximum price per unit in INR"
                            },
                            "limit": {
                                "type": "integer",
                                "description": "Max number of results to return (default 10, max 50)"
                            }
                        }
                    }
                }
            }
        },
        {
            "toolSpec": {
                "name": "get_price_stats",
                "description": (
                    "Get current market price statistics (min, max, average) for a specific produce. "
                    "Always call this before making any price claims or price comparisons."
                ),
                "inputSchema": {
                    "json": {
                        "type": "object",
                        "properties": {
                            "product_name": {
                                "type": "string",
                                "description": "Exact produce name e.g. 'Tomatoes', 'Wheat', 'Onion'"
                            }
                        },
                        "required": ["product_name"]
                    }
                }
            }
        },
        {
            "toolSpec": {
                "name": "get_listing_bids",
                "description": (
                    "Get all current bids on a specific listing. "
                    "Use this to help the buyer decide a competitive bid amount. "
                    "Requires a listing_id number."
                ),
                "inputSchema": {
                    "json": {
                        "type": "object",
                        "properties": {
                            "listing_id": {
                                "type": "integer",
                                "description": "The numeric ID of the listing to check bids for"
                            }
                        },
                        "required": ["listing_id"]
                    }
                }
            }
        },
        {
            "toolSpec": {
                "name": "get_available_categories",
                "description": "Get all produce categories currently listed in the marketplace.",
                "inputSchema": {
                    "json": {
                        "type": "object",
                        "properties": {}
                    }
                }
            }
        }
    ]
}


def _run_tool(name, inputs, buyer_token=None):
    try:
        if name == "search_listings":
            return search_listings(**inputs)
        elif name == "get_price_stats":
            return get_price_stats(**inputs)
        elif name == "get_listing_bids":
            return get_listing_bids(buyer_token=buyer_token, **inputs)
        elif name == "get_available_categories":
            return get_available_categories()
        return {"error": f"Unknown tool: {name}"}
    except Exception as e:
        return {"error": f"Tool '{name}' failed: {str(e)}"}


def get_response(message, buyer_token=None, history=None):
    bedrock = boto3.client(
        'bedrock-runtime',
        region_name=os.environ.get('BEDROCK_REGION', 'us-east-1')
    )
    model_id = os.environ.get('MODEL_ID', 'amazon.nova-lite-v1:0')

    messages = []
    for h in (history or [])[-20:]:  # keep last 10 exchanges (20 messages)
        messages.append({"role": h["role"], "content": [{"text": h["text"]}]})
    messages.append({"role": "user", "content": [{"text": message}]})

    for _ in range(6):
        response = bedrock.converse(
            modelId=model_id,
            messages=messages,
            system=[{"text": SYSTEM_PROMPT}],
            toolConfig=TOOL_CONFIG,
            inferenceConfig={"maxTokens": 600, "temperature": 0.1}
        )

        stop_reason = response['stopReason']
        assistant_msg = response['output']['message']
        messages.append(assistant_msg)

        if stop_reason == 'end_turn':
            for block in assistant_msg.get('content', []):
                if 'text' in block:
                    return block['text']
            return "I couldn't generate a response. Please try again."

        if stop_reason == 'tool_use':
            tool_results = []
            for block in assistant_msg.get('content', []):
                if 'toolUse' not in block:
                    continue
                name = block['toolUse']['name']
                inputs = block['toolUse']['input']
                use_id = block['toolUse']['toolUseId']
                result = _run_tool(name, inputs, buyer_token)
                tool_results.append({
                    "toolResult": {
                        "toolUseId": use_id,
                        "content": [{"text": json.dumps(result, ensure_ascii=False)}]
                    }
                })
            if tool_results:
                messages.append({"role": "user", "content": tool_results})
            else:
                break

    return "I had trouble processing your request. Please try again."
