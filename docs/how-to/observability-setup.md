# How to Set Up Observability for Your Service

## When to Use This Guide

Use this guide when:
- Adding CloudWatch dashboards or alarms for a new service
- Configuring structured logging from ECS/EKS workloads
- Setting up PagerDuty alerts for production incidents
- Querying application logs or traces in OpenSearch / X-Ray

---

## Observability Stack Overview

```
Application (ECS / EKS)
    │
    ├── Logs ──────────────► CloudWatch Logs → OpenSearch (7-day → 90-day archival)
    ├── Metrics ────────────► CloudWatch Metrics → Dashboards + Alarms → SNS → PagerDuty
    └── Traces ─────────────► X-Ray → Service Map + Latency analysis
```

---

## Step 1 — Structured Logging

All services must emit structured (JSON) logs so CloudWatch Insights and OpenSearch can query them.

### ECS — awslogs driver (already configured in task definition)

```json
"logConfiguration": {
  "logDriver": "awslogs",
  "options": {
    "awslogs-group": "/cap/dev/payment-api",
    "awslogs-region": "us-east-1",
    "awslogs-stream-prefix": "ecs"
  }
}
```

Create the log group in Terraform (module `cloudwatch`):

```hcl
resource "aws_cloudwatch_log_group" "service" {
  name              = "/cap/${var.environment}/payment-api"
  retention_in_days = var.environment == "prod" ? 365 : 30
  kms_key_id        = var.kms_key_arn
}
```

### EKS — Fluent Bit (installed as DaemonSet via EKS addon)

Logs are automatically forwarded from pods to CloudWatch. Log group pattern:
- `/aws/containerinsights/cap-{env}-eks/application`

### Structured log format

```json
{
  "timestamp": "2026-05-28T10:00:00Z",
  "level": "INFO",
  "service": "payment-api",
  "trace_id": "x-amzn-trace-id",
  "request_id": "uuid",
  "message": "Payment processed",
  "amount": 99.99,
  "currency": "USD"
}
```

---

## Step 2 — CloudWatch Metrics and Alarms

### Add service-specific alarms

Add to `monitoring/cloudwatch/alarms/security-alarms.json` or create a new file:

```json
[
  {
    "AlarmName": "cap-dev-payment-api-error-rate",
    "AlarmDescription": "Payment API error rate exceeds 5%",
    "MetricName": "5XXError",
    "Namespace": "AWS/ApplicationELB",
    "Dimensions": [
      {"Name": "LoadBalancer", "Value": "app/cap-dev-alb/xxxxxx"}
    ],
    "Statistic": "Sum",
    "Period": 60,
    "EvaluationPeriods": 3,
    "Threshold": 10,
    "ComparisonOperator": "GreaterThanThreshold",
    "AlarmActions": ["arn:aws:sns:us-east-1:ACCOUNT:cap-dev-alerts"],
    "TreatMissingData": "notBreaching"
  },
  {
    "AlarmName": "cap-dev-payment-api-latency-p99",
    "AlarmDescription": "Payment API p99 latency exceeds 2s",
    "MetricName": "TargetResponseTime",
    "Namespace": "AWS/ApplicationELB",
    "ExtendedStatistic": "p99",
    "Period": 60,
    "EvaluationPeriods": 5,
    "Threshold": 2.0,
    "ComparisonOperator": "GreaterThanThreshold",
    "AlarmActions": ["arn:aws:sns:us-east-1:ACCOUNT:cap-dev-alerts"]
  }
]
```

### Custom application metrics

Emit custom metrics from your application:

```python
import boto3

cloudwatch = boto3.client("cloudwatch", region_name="us-east-1")

def record_payment(amount: float, currency: str):
    cloudwatch.put_metric_data(
        Namespace="CAP/PaymentAPI",
        MetricData=[
            {
                "MetricName": "PaymentProcessed",
                "Dimensions": [
                    {"Name": "Environment", "Value": "dev"},
                    {"Name": "Currency", "Value": currency}
                ],
                "Value": amount,
                "Unit": "None"
            }
        ]
    )
```

```typescript
// TypeScript / Node.js
import { CloudWatch } from "@aws-sdk/client-cloudwatch";
const cw = new CloudWatch({ region: "us-east-1" });

await cw.putMetricData({
  Namespace: "CAP/PaymentAPI",
  MetricData: [{ MetricName: "PaymentProcessed", Value: amount, Unit: "None" }]
});
```

---

## Step 3 — CloudWatch Dashboard

Add your service to the platform dashboard or create a service-specific one:

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "title": "Payment API — Request Rate",
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/cap-dev-alb/xxxx"]
        ],
        "period": 60,
        "stat": "Sum",
        "view": "timeSeries"
      }
    },
    {
      "type": "log",
      "properties": {
        "title": "Payment API — Error Logs",
        "query": "SOURCE '/cap/dev/payment-api' | filter level = 'ERROR' | stats count(*) by bin(5m)",
        "region": "us-east-1",
        "view": "timeSeries"
      }
    }
  ]
}
```

Save to `monitoring/cloudwatch/dashboards/payment-api.json` and apply via Terraform:

```hcl
resource "aws_cloudwatch_dashboard" "payment_api" {
  dashboard_name = "cap-${var.environment}-payment-api"
  dashboard_body = file("${path.root}/../../../monitoring/cloudwatch/dashboards/payment-api.json")
}
```

---

## Step 4 — X-Ray Distributed Tracing

### Enable tracing in ECS

In the task definition, add the X-Ray daemon sidecar:

```json
{
  "name": "xray-daemon",
  "image": "amazon/aws-xray-daemon",
  "cpu": 32,
  "memoryReservation": 256,
  "portMappings": [{"containerPort": 2000, "protocol": "udp"}]
}
```

### Instrument your application

```python
# Python — AWS X-Ray SDK
from aws_xray_sdk.core import xray_recorder, patch_all
patch_all()  # auto-instruments boto3, requests, httplib

@xray_recorder.capture("process_payment")
def process_payment(amount: float):
    # subsegment automatically created
    result = call_stripe_api(amount)
    return result
```

```typescript
// TypeScript
import AWSXRay from "aws-xray-sdk";
const https = AWSXRay.captureHTTPs(require("https"));

app.use(AWSXRay.express.openSegment("PaymentAPI"));
// ... routes
app.use(AWSXRay.express.closeSegment());
```

### View traces

```
AWS Console → X-Ray → Service Map → select cap-{env}-payment-api
```

Or query via CLI:
```bash
aws xray get-service-graph \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

---

## Step 5 — CloudWatch Logs Insights Queries

Useful queries for your daily operational use:

```bash
# Error rate in last hour
aws logs start-query \
  --log-group-name "/cap/dev/payment-api" \
  --start-time $(date -d "1 hour ago" +%s) \
  --end-time $(date +%s) \
  --query-string 'filter level = "ERROR" | stats count(*) as errors by bin(5m)'

# Slow requests (>1s)
--query-string 'filter duration > 1000 | stats avg(duration), max(duration), count(*) by service'

# Unique error messages
--query-string 'filter level = "ERROR" | stats count(*) as count by message | sort count desc | limit 20'
```

---

## PagerDuty Integration

Security Hub CRITICAL/HIGH findings and CloudWatch composite alarms route to PagerDuty via SNS:

```
Security Hub finding (CRITICAL/HIGH)
  → EventBridge rule (security/scps-related)
  → SNS topic: cap-{env}-security-alerts
  → PagerDuty: cap-platform-engineering
```

To add a new routing rule:
```hcl
# In terraform/modules/security-hub/findings-routing.tf:
resource "aws_cloudwatch_event_rule" "payment_api_critical" {
  name        = "cap-${var.environment}-payment-api-critical"
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = { Label = ["CRITICAL"] }
        ProductFields = { "aws/securityhub/ProductName" = ["Payment API"] }
      }
    }
  })
}
```

---

## Retention and Archival Policy

| Log Group | Dev | Staging | Prod |
|-----------|-----|---------|------|
| Application logs | 30 days | 90 days | 365 days |
| VPC flow logs | 30 days | 90 days | 365 days |
| CloudTrail | N/A (centralized S3) | N/A | 7 years (S3) |
| EKS control plane | 30 days | 90 days | 365 days |

Logs are encrypted with the environment's `alias/cap/{env}/kms/cloudwatch` key.
