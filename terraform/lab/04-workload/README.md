# Lab Layer 04 — Sample Workload

> **Navigation:** [Lab README](../README.md) | [Request Path Diagram](../../../docs/architecture/diagrams/04-request-path.md) | [ADR-0008 SSM Handoff](../../../docs/adr/0008-ssm-parameter-store-handoff.md)

A small serverless API that exercises the platform end to end: request → API
Gateway → Lambda → DynamoDB, with structured logs, traces, metrics, alarms and
an SSM handoff to the CDK layer.

## What it creates

| Resource | Purpose | Free-tier position |
|----------|---------|--------------------|
| HTTP API + 3 routes | Public entry point, throttled | 1M requests/month free |
| Lambda (Python 3.12, arm64) | Request handler, concurrency capped at 5 | 1M requests + 400k GB-s/month free |
| DynamoDB table (on-demand, TTL) | Storage; records self-expire after 7 days | 25 GB free, idle table costs nothing |
| 2 CloudWatch log groups | 7-day retention set explicitly | 5 GB ingestion free |
| 4 CloudWatch alarms | Errors, throttles, 5xx, request volume | 10 alarms free |
| 1 CloudWatch dashboard | Platform health | 3 dashboards free |
| SNS topic | Alarm routing | 1M publishes free |
| 8 SSM parameters | Terraform → CDK handoff | Standard tier free |

## Apply

```bash
cd terraform/lab/04-workload
terraform init
terraform plan  -out=tfplan
terraform apply tfplan

# Prove it works
terraform output -raw smoke_test | bash
```

Expected:

```json
{"status": "ok", "environment": "lab"}
{"pk": "…", "name": "first", "created_at": 1753..., "expires_at": 1754...}
{"items": [...], "count": 1}
```

## Cost guardrails built into this layer

Three independent limits, because a single one is a single point of failure:

1. **API Gateway throttling** — 5 requests/second steady, 10 burst. Caps the
   arrival rate.
2. **Lambda reserved concurrency** — 5 simultaneous executions. Caps compute
   even if throttling is misconfigured.
3. **DynamoDB TTL** — records expire after 7 days, so storage cannot creep past
   the free tier while unattended.

Plus a CloudWatch alarm that fires above 1,000 requests per five minutes, which
is far beyond anything a lab produces.

## Why the API is unauthenticated

The routes are open so that `curl` demonstrates the path without credential
setup. That is a deliberate lab choice, not a recommendation — it is why the
throttles above exist. For anything real, add IAM authorisation:

```hcl
resource "aws_apigatewayv2_route" "routes" {
  # …
  authorization_type = "AWS_IAM"
}
```

and sign requests with SigV4. JWT authorisation against Cognito or an external
IdP is the other supported option. Recorded in
[known issues](../../../docs/security/known-issues.md).

## Why the function is not in the VPC

`attach_to_vpc` defaults to `false`. The lab VPC has no NAT gateway, so a
VPC-attached function reaches S3 and DynamoDB via gateway endpoints and nothing
else. Outside the VPC the function has normal egress and no ENI cold-start
penalty, at no cost. A function that needs to reach RDS in the isolated tier
must be attached — and that is when NAT or interface endpoints stop being
optional.

## Verification

```bash
aws lambda get-function-configuration --function-name "$(terraform output -raw function_name)" \
  --query '{Runtime:Runtime,Arch:Architectures,Concurrency:ReservedConcurrentExecutions,Tracing:TracingConfig.Mode}'

aws dynamodb describe-time-to-live --table-name "$(terraform output -raw table_name)"

aws apigatewayv2 get-stage --api-id "$(terraform output -raw api_id)" --stage-name '$default' \
  --query 'DefaultRouteSettings'

aws ssm get-parameters-by-path --path "/cap/lab" --recursive \
  --query 'Parameters[].Name' --output table
```
