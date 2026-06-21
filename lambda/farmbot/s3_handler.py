import boto3
import json
import os
from datetime import datetime, timezone

S3_BUCKET = os.environ.get('S3_BUCKET_NAME', 'agriconnect-farmbot-logs')
AWS_REGION = os.environ.get('AWS_REGION', 'ap-south-1')

_s3 = None

def _get_client():
    global _s3
    if _s3 is None:
        _s3 = boto3.client('s3', region_name=AWS_REGION)
    return _s3


def store_photo(farmer_id, image_bytes):
    client = _get_client()
    ts = int(datetime.now(timezone.utc).timestamp())
    key = f"photos/{farmer_id}/{ts}.jpg"
    client.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=image_bytes,
        ContentType='image/jpeg'
    )
    return key


def store_chat_log(farmer_id, message, photo_key, response_text, is_critical):
    client = _get_client()
    ts = datetime.now(timezone.utc)
    key = f"chatlogs/{farmer_id}/{int(ts.timestamp())}.json"

    log = {
        "farmer_id": farmer_id,
        "timestamp": ts.isoformat(),
        "input": {
            "text": message or "",
            "image_stored": photo_key
        },
        "output": {
            "full_response": response_text,
            "critical_flag": is_critical
        }
    }

    client.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=json.dumps(log, ensure_ascii=False),
        ContentType='application/json'
    )
