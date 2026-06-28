import json
import os
import hashlib
import time
import boto3

# Initialize SQS client outside the handler for connection reuse
sqs = boto3.client('sqs')
QUEUE_URL = os.environ.get('SQS_QUEUE_URL')

def handler(event, context):
    print("Received event:", json.dumps(event))
    
    # 1. Extract request payload
    body_str = event.get('body', '{}')
    if event.get('isBase64Encoded', False):
        import base64
        body_str = base64.b64decode(body_str).decode('utf-8')
        
    try:
        payload = json.loads(body_str)
    except Exception as e:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid JSON payload', 'details': str(e)})
        }
        
    alerts = payload.get('alerts', [])
    if not alerts:
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'No alerts found in webhook payload'})
        }
        
    processed_count = 0
    errors = []
    
    # 2. Iterate and process each alert in the webhook
    for alert in alerts:
        labels = alert.get('labels', {})
        annotations = alert.get('annotations', {})
        
        tenant_id = labels.get('tenant_id', 'common')
        service = labels.get('service', 'unknown')
        env = labels.get('env', 'sandbox')
        alert_name = labels.get('alertname', 'generic-alert')
        severity = labels.get('severity', 'warning')
        
        summary = annotations.get('summary', '')
        description = annotations.get('description', '')
        starts_at = alert.get('startsAt', '')
        
        # 3. Create unique fingerprint for deduplication
        # Combining alert properties and startsAt to allow distinct alerts over time
        fingerprint_raw = f"{tenant_id}:{service}:{env}:{alert_name}:{starts_at}"
        alert_fingerprint = hashlib.sha256(fingerprint_raw.encode('utf-8')).hexdigest()
        
        # 4. Define correlation group key for sequencing (MessageGroupId)
        correlation_key = f"{tenant_id}#{service}"
        
        # 5. Build canonical normalized alert payload
        normalized_alert = {
            'incident_id': alert_fingerprint,
            'tenant_id': tenant_id,
            'service': service,
            'env': env,
            'alertname': alert_name,
            'severity': severity,
            'summary': summary,
            'description': description,
            'timestamp': starts_at if starts_at else time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'raw_payload': alert,
            'ttl': int(time.time()) + (90 * 86400) # 90 days retention
        }
        
        # 6. Dispatch message to SQS FIFO queue
        try:
            response = sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=json.dumps(normalized_alert),
                MessageGroupId=correlation_key,
                MessageDeduplicationId=alert_fingerprint
            )
            processed_count += 1
            print(f"Dispatched alert {alert_fingerprint} to SQS. MsgId: {response.get('MessageId')}")
        except Exception as e:
            err_msg = f"Failed to send alert {alert_fingerprint} to SQS: {str(e)}"
            print(err_msg)
            errors.append(err_msg)
            
    # 7. Final response compilation
    if errors and processed_count == 0:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to queue any alerts', 'details': errors})
        }
        
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Alerts processed successfully',
            'processed': processed_count,
            'failed': len(errors),
            'errors': errors
        })
    }
