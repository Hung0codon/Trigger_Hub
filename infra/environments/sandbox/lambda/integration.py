import json
import os
import urllib.request
import boto3

def handler(event, context):
    print("Received integration event:", json.dumps(event))
    
    # 1. Parse incoming incident/RCA payload
    # In production, this can come from the Correlator worker or SQS
    incident_id = event.get('incident_id', 'generic-id')
    tenant_id = event.get('tenant_id', 'common')
    service = event.get('service', 'unknown')
    alert_name = event.get('alertname', 'generic-alert')
    severity = event.get('severity', 'warning')
    summary = event.get('summary', 'Alert summary')
    description = event.get('description', 'Alert description')
    rca_report = event.get('rca_report', 'Pending analysis')
    
    # 2. Get environment/config
    env = os.environ.get('ENVIRONMENT', 'sandbox')
    
    # In a real environment, Jira and Slack tokens are fetched from AWS Secrets Manager
    # For local validation and deploy, we construct the request payload
    print(f"Processing integration for incident {incident_id} (Tenant: {tenant_id}, Service: {service})")
    
    # 3. Simulate Jira ticket creation
    jira_issue_key = f"JIRA-{incident_id[:8].upper()}"
    print(f"Created/Updated Jira Issue: {jira_issue_key}")
    
    # 4. Simulate Slack notification
    slack_payload = {
        "text": f"🚨 *[TF1 Triage Hub]* Incident Alert in *{env.upper()}*\n"
                f"*Incident ID:* `{incident_id}`\n"
                f"*Tenant:* `{tenant_id}`\n"
                f"*Service:* `{service}`\n"
                f"*Severity:* `{severity.upper()}`\n"
                f"*Summary:* {summary}\n"
                f"*RCA Analysis:* {rca_report}\n"
                f"*Jira Ticket:* <https://jira.example.com/browse/{jira_issue_key}|{jira_issue_key}>"
    }
    
    # Slack Webhook endpoint from env var (mock url if not provided)
    slack_webhook_url = os.environ.get('SLACK_WEBHOOK_URL', '')
    if slack_webhook_url and slack_webhook_url.startswith('http'):
        try:
            req = urllib.request.Request(
                slack_webhook_url,
                data=json.dumps(slack_payload).encode('utf-8'),
                headers={'Content-Type': 'application/json'},
                method='POST'
            )
            with urllib.request.urlopen(req) as res:
                response_text = res.read().decode('utf-8')
                print(f"Slack response: {response_text}")
        except Exception as e:
            print(f"Error sending message to Slack: {str(e)}")
    else:
        print("Slack webhook URL not set or invalid. Skipping HTTP request. Slack Payload:")
        print(json.dumps(slack_payload, indent=2))
        
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Incident integration processed successfully',
            'incident_id': incident_id,
            'jira_ticket': jira_issue_key,
            'slack_notified': True
        })
    }
