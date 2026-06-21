import boto3
import json
import os
from system_prompt import SYSTEM_PROMPT

BEDROCK_REGION = os.environ.get('BEDROCK_REGION', 'us-east-1')
MODEL_ID = os.environ.get('MODEL_ID', 'amazon.nova-lite-v1:0')

_bedrock = None

def _get_client():
    global _bedrock
    if _bedrock is None:
        _bedrock = boto3.client('bedrock-runtime', region_name=BEDROCK_REGION)
    return _bedrock


def call_nova_lite(payload):
    client = _get_client()
    response = client.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps(payload)
    )
    result = json.loads(response['body'].read())
    return result['output']['message']['content'][0]['text']


def build_text_payload(message, history=None):
    messages = []
    for h in (history or [])[-20:]:  # keep last 10 exchanges (20 messages)
        messages.append({"role": h["role"], "content": [{"text": h["text"]}]})
    messages.append({
        "role": "user",
        "content": [{"text": message or "Hello, can you help me with my crops?"}]
    })
    return {
        "messages": messages,
        "system": [{"text": SYSTEM_PROMPT}],
        "inferenceConfig": {"maxTokens": 600, "temperature": 0.2, "topP": 0.9}
    }


def _detect_format(image_b64):
    if image_b64.startswith('/9j/'):
        return 'jpeg'
    if image_b64.startswith('iVBORw0K'):
        return 'png'
    if image_b64.startswith('UklGR'):
        return 'webp'
    if image_b64.startswith('R0lGO'):
        return 'gif'
    return 'jpeg'


def build_multimodal_payload(message, image_b64, history=None):
    fmt = _detect_format(image_b64)
    messages = []
    for h in (history or [])[-20:]:
        messages.append({"role": h["role"], "content": [{"text": h["text"]}]})
    messages.append({
        "role": "user",
        "content": [
            {"image": {"format": fmt, "source": {"bytes": image_b64}}},
            {"text": message or "What is wrong with this plant? Give diagnosis and treatment."}
        ]
    })
    return {
        "messages": messages,
        "system": [{"text": SYSTEM_PROMPT}],
        "inferenceConfig": {"maxTokens": 600, "temperature": 0.2, "topP": 0.9}
    }
