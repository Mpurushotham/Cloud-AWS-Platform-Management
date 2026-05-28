# How to Manage Secrets and Rotation

## When to Use This Guide

Use this guide when:
- Storing a new secret (API key, database password, OAuth token)
- Rotating a compromised or expiring credential
- Accessing secrets from application code or Kubernetes pods
- Setting up automatic rotation for RDS or other managed services

**Never:**
- Commit secrets to git (gitleaks + trufflehog will block the PR)
- Store secrets in environment variables in ECS task definitions or Kubernetes manifests
- Use IAM access keys — use OIDC or IRSA instead

---

## Where Secrets Live

| Secret Type | Storage | Rotation |
|-------------|---------|---------|
| RDS master password | Secrets Manager (managed) | Automatic (Terraform `manage_master_user_password=true`) |
| Application API keys | Secrets Manager | Manual or Lambda rotation function |
| Container registry credentials | IAM + ECR (no password needed) | N/A (IAM auth) |
| TLS certificates | ACM | Automatic (ACM managed) |
| SSH keys | None — use SSM Session Manager | N/A |
| CI/CD credentials | GitHub OIDC (no secret) | N/A |

---

## Storing a New Secret

### Step 1 — Create in Secrets Manager

```bash
# Simple string secret
aws secretsmanager create-secret \
  --name "cap/dev/payment-api/stripe-api-key" \
  --description "Stripe API key for payment-api in dev" \
  --secret-string "sk_test_xxxxxx" \
  --kms-key-id alias/cap/dev/kms/secrets-manager \
  --region us-east-1

# JSON secret (multiple values)
aws secretsmanager create-secret \
  --name "cap/dev/payment-api/db-credentials" \
  --secret-string '{"username":"app_user","password":"change-me"}' \
  --kms-key-id alias/cap/dev/kms/secrets-manager
```

**Naming convention:** `cap/{environment}/{service}/{secret-name}`

### Step 2 — Add IAM policy for the service to read the secret

In your IRSA role policy or ECS task role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:cap/dev/payment-api/*"
    },
    {
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID"
    }
  ]
}
```

---

## Accessing Secrets from Application Code

### ECS — Using Secrets Manager injection

In your ECS task definition (`ecs/task-definitions/api.json`):

```json
"secrets": [
  {
    "name": "STRIPE_API_KEY",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:cap/dev/payment-api/stripe-api-key"
  },
  {
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:cap/dev/payment-api/db-credentials:password::"
  }
]
```

The secret is injected as an environment variable at task startup. The task role must have `GetSecretValue` permission.

### EKS — Using External Secrets Operator

Install the External Secrets Operator (add to `kubernetes/helm-charts/`):

```yaml
# ExternalSecret manifest
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: payment-api-secrets
  namespace: applications
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: payment-api-secrets    # creates a Kubernetes Secret
  data:
    - secretKey: stripe-api-key
      remoteRef:
        key: cap/dev/payment-api/stripe-api-key
```

Reference in pod spec:
```yaml
env:
  - name: STRIPE_API_KEY
    valueFrom:
      secretKeyRef:
        name: payment-api-secrets
        key: stripe-api-key
```

### Python / boto3

```python
import boto3
import json

def get_secret(secret_name: str, region: str = "us-east-1") -> dict:
    client = boto3.client("secretsmanager", region_name=region)
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])

creds = get_secret("cap/dev/payment-api/db-credentials")
password = creds["password"]
```

---

## Rotating Secrets

### RDS — Automatic Rotation (already configured)

RDS uses Terraform's `manage_master_user_password = true`. Secrets Manager rotates the password automatically every 30 days using a Lambda managed by AWS.

To trigger manual rotation:
```bash
aws secretsmanager rotate-secret \
  --secret-id "cap/prod/rds/master-credentials" \
  --rotate-immediately
```

Verify rotation completed:
```bash
aws secretsmanager describe-secret \
  --secret-id "cap/prod/rds/master-credentials" \
  --query '{LastRotatedDate:LastRotatedDate,RotationEnabled:RotationEnabled}'
```

### API Keys — Manual Rotation

Use the rotation script:
```bash
./scripts/rotate-secrets.sh cap/dev/payment-api/stripe-api-key NEW_KEY_VALUE
```

Or manually:
```bash
# 1. Put the new value as a new version
aws secretsmanager put-secret-value \
  --secret-id "cap/dev/payment-api/stripe-api-key" \
  --secret-string "sk_test_new_key_value" \
  --version-stages AWSPENDING

# 2. Test your application with the new key

# 3. Promote to current
aws secretsmanager update-secret-version-stage \
  --secret-id "cap/dev/payment-api/stripe-api-key" \
  --version-stage AWSCURRENT \
  --move-to-version-id $(aws secretsmanager describe-secret \
    --secret-id "cap/dev/payment-api/stripe-api-key" \
    --query 'VersionIdsToStages' | jq -r 'to_entries | .[] | select(.value[] == "AWSPENDING") | .key')
```

### Compromised Credential Emergency Rotation

If a secret is suspected to be compromised:

```bash
# 1. Immediately revoke — block the compromised key at the source (Stripe/GitHub/etc.)

# 2. Revoke any active AWS sessions that used it
aws iam put-role-policy \
  --role-name ROLE_NAME \
  --policy-name EmergencyDeny \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'

# 3. Issue new secret
aws secretsmanager put-secret-value \
  --secret-id SECRET_ARN \
  --secret-string "NEW_VALUE"

# 4. Restart ECS services / rollout restart Kubernetes pods
aws ecs update-service --cluster cap-dev-ecs --service payment-api --force-new-deployment

kubectl rollout restart deployment/payment-api -n applications

# 5. Remove the emergency deny policy after verifying new creds work
aws iam delete-role-policy --role-name ROLE_NAME --policy-name EmergencyDeny

# 6. Check CloudTrail for any unauthorized use of the compromised secret
# See incident-response.md for Athena query template
```

---

## Auditing Secret Access

All Secrets Manager API calls are logged to CloudTrail. Query via Athena:

```sql
SELECT
  eventtime,
  sourceipaddress,
  useridentity.arn,
  requestparameters
FROM cloudtrail_logs
WHERE eventsource = 'secretsmanager.amazonaws.com'
  AND eventname = 'GetSecretValue'
  AND requestparameters LIKE '%stripe-api-key%'
  AND eventtime > '2026-01-01T00:00:00Z'
ORDER BY eventtime DESC
LIMIT 50;
```

---

## KMS Key Rotation

All KMS keys in this platform have `enable_key_rotation = true`, which rotates the key material automatically every year. The key ID and alias never change — applications see no disruption.

```bash
# Verify rotation is enabled for all keys
./scripts/key-rotation-check.py

# Output: table showing each key alias and rotation status
# Any key showing rotation=false is a compliance violation (flagged by OPA + Prowler)
```
