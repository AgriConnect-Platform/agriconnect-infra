import json
import boto3
import os
import base64

bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("BEDROCK_REGION", "us-east-1"))

SYSTEM_PROMPT = """You are FarmBot, an expert AI assistant for AgriConnect farmers in India.

Your expertise covers:
- Indian crops: rice, wheat, sugarcane, cotton, pulses, vegetables, fruits, spices
- Crop disease identification from images — spots, wilting, discolouration, rot, pest damage
- Soil health: NPK ratios, pH, organic matter, soil types
- Irrigation: drip, flood, scheduling based on crop stage and weather
- Fertilizers: organic (vermicompost, neem cake, compost) and chemical (urea, DAP, MOP, SSP)
- Pest management: IPM, organic solutions, chemical pesticides (safety and dosage)
- Weather-based farming: monsoon timing, frost protection, drought management
- Harvest and market timing: when to harvest for best yield and price
- Government schemes: PM-KISAN, Fasal Bima Yojana, MSP rates, Kisan Credit Card

When an image is provided:
1. Carefully describe what you observe (leaf colour, texture, spots, patterns, affected areas)
2. Give your most likely diagnosis (disease name, deficiency, or pest)
3. Provide step-by-step treatment (organic options first, then chemical if needed)
4. State urgency: LOW / MEDIUM / HIGH / CRITICAL
5. If CRITICAL, advise contacting a local agricultural officer immediately

Always be practical, clear, and helpful. Respond in simple English suitable for Indian farmers."""


def detect_image_format(image_bytes: bytes) -> str:
    if image_bytes[:8] == b'\x89PNG\r\n\x1a\n':
        return 'png'
    if image_bytes[:2] == b'\xff\xd8':
        return 'jpeg'
    if image_bytes[:6] in (b'GIF87a', b'GIF89a'):
        return 'gif'
    if image_bytes[:4] == b'RIFF' and image_bytes[8:12] == b'WEBP':
        return 'webp'
    return 'jpeg'


def lambda_handler(event, context):
    try:
        body       = json.loads(event.get("body", "{}"))
        message    = body.get("message", "").strip()
        image_b64  = body.get("image")        # raw base64, no data: prefix
        history    = body.get("history", [])  # [{role:"user"|"assistant", text:"..."}]

        # Build conversation history
        messages = []
        for turn in history:
            role = "user" if turn.get("role") == "user" else "assistant"
            messages.append({
                "role": role,
                "content": [{"text": turn.get("text", "")}]
            })

        # Build current turn content (image + text)
        content = []
        if image_b64:
            image_bytes = base64.b64decode(image_b64)
            fmt = detect_image_format(image_bytes)
            content.append({
                "image": {
                    "format": fmt,
                    "source": {"bytes": image_bytes}
                }
            })

        if message:
            content.append({"text": message})
        elif image_b64:
            # Image uploaded with no text — prompt for analysis
            content.append({
                "text": "Please analyse this crop image. Describe what you see, identify any diseases, deficiencies or pest damage, and provide treatment recommendations with urgency level."
            })

        if not content:
            content = [{"text": "Hello"}]

        messages.append({"role": "user", "content": content})

        response = bedrock.converse(
            modelId=os.environ.get("MODEL_ID", "amazon.nova-lite-v1:0"),
            messages=messages,
            system=[{"text": SYSTEM_PROMPT}],
            inferenceConfig={"maxTokens": 1024, "temperature": 0.7}
        )

        reply = response["output"]["message"]["content"][0]["text"]

        # Flag critical plant health issues
        critical_terms = ["critical", "severe", "blight", "wilt", "rot", "rust", "dying", "emergency"]
        is_critical = bool(image_b64) and any(t in reply.lower() for t in critical_terms)

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({"response": reply, "critical": is_critical})
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"response": f"Sorry, I couldn't process your request right now. Please try again.", "critical": False})
        }
