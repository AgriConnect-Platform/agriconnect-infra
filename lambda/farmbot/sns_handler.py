import boto3
import os

SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
AWS_REGION = os.environ.get('AWS_REGION', 'ap-south-1')

_sns = None

def _get_client():
    global _sns
    if _sns is None:
        _sns = boto3.client('sns', region_name=AWS_REGION)
    return _sns


def trigger_critical_alert(farmer_id, problem_text, bot_response):
    if not SNS_TOPIC_ARN:
        print('SNS_TOPIC_ARN not set — skipping critical alert')
        return

    client = _get_client()
    diagnosis_preview = bot_response[:300] if bot_response else ''

    message = (
        f"CRITICAL CROP ISSUE DETECTED via FarmBot\n\n"
        f"Farmer ID: {farmer_id}\n"
        f"Problem reported: {problem_text or '(photo only)'}\n\n"
        f"FarmBot diagnosis:\n{diagnosis_preview}\n\n"
        f"Action needed: Please contact the farmer immediately."
    )

    client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="[FarmBot CRITICAL] Urgent crop issue reported",
        Message=message
    )
    print(f'Critical alert sent for farmer {farmer_id}')
