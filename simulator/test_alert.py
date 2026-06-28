import boto3
import json
import sys

def send_test_alert():
    client = boto3.client('lambda', region_name='us-east-1')
    
    # Prometheus Alert payload
    alert_payload = {
        "receiver": "webhook",
        "status": "firing",
        "alerts": [
            {
                "status": "firing",
                "labels": {
                    "tenant_id": "tenant-a",
                    "service": "tf1-ai-triage-engine",
                    "env": "sandbox",
                    "alertname": "CPUThresholdExceeded",
                    "severity": "critical"
                },
                "annotations": {
                    "summary": "High CPU utilization detected on pod",
                    "description": "CPU usage on pod is above 85% for the last 5 minutes."
                },
                "startsAt": "2026-06-28T12:00:00Z",
                "endsAt": "0001-01-01T00:00:00Z"
            }
        ]
    }
    
    # Emulate AWS Function URL Event structure by putting payload in "body"
    lambda_event = {
        "body": json.dumps(alert_payload),
        "isBase64Encoded": False
    }
    
    function_name = 'tf1-cdo05-sandbox-ingest-handler'
    print(f"Sending test alert (emulated proxy event) to Lambda: {function_name}...")
    
    try:
        response = client.invoke(
            FunctionName=function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps(lambda_event)
        )
        
        response_payload = json.loads(response['Payload'].read().decode('utf-8'))
        print(f"HTTP Response Status Code: {response_payload.get('statusCode')}")
        
        body = json.loads(response_payload.get('body'))
        print("Response Body:")
        print(json.dumps(body, indent=2))
        print("\nSuccess! Incident pipeline triggered.")
        print("Check CloudWatch Logs for 'tf1-cdo05-sandbox-lambda-integration-role' to see mock Slack/Jira processing logs.")
    except Exception as e:
        print(f"Error invoking Lambda: {str(e)}")

if __name__ == '__main__':
    send_test_alert()
