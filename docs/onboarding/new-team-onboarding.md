# New Team Onboarding Guide

## Welcome to CAP (Cloud-AWS-Platform)

This guide gets your team from zero to deploying on the platform in one day.

## Step 1: Get Access (30 minutes)

1. Request SSO access from the platform team:
   - Submit request to `#platform-team` Slack channel
   - Required info: team name, GitHub usernames, manager approval
2. Accept IAM Identity Center invitation email
3. Log in at: `https://your-org.awsapps.com/start`
4. You'll get `Developer` access to dev/staging accounts initially

## Step 2: Set Up Local Environment (30 minutes)

```bash
# Clone the platform repo
git clone git@github.com:your-org/Cloud-AWS-Platform-Management.git
cd Cloud-AWS-Platform-Management

# Run bootstrap script
./scripts/bootstrap.sh

# Configure AWS CLI with SSO
aws configure sso
# Profile name: cap-dev
# SSO start URL: https://your-org.awsapps.com/start
# Region: us-east-1
# Output format: json
```

## Step 3: Choose Your Golden Path (15 minutes)

| Use Case | Template |
|----------|---------|
| HTTP API backend | `idp/templates/rest-api-service` |
| Background worker | `idp/templates/ecs-microservice` |
| Kubernetes workload | `idp/templates/eks-workload` |
| Data pipeline | `idp/templates/data-pipeline` |

```bash
pip install cookiecutter
cookiecutter idp/templates/rest-api-service/
```

## Step 4: Configure Your Service Repository

The cookiecutter template generates a repo with:
- Dockerfile (pre-hardened, non-root)
- CDK stack for your service
- GitHub Actions workflow
- Pre-commit hooks

Add your team's GitHub repo to the OIDC trust policy:
```bash
# Open a PR adding your repo to terraform/bootstrap/oidc.tf
# Platform team will review and merge
```

## Step 5: Deploy to Dev

```bash
# Build and push your container image
aws ecr get-login-password --region us-east-1 | docker login --username AWS \
  --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

docker build -t cap-dev-your-service:latest .
docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/cap-dev-your-service:latest

# Deploy via CDK
cd cdk && npx cdk deploy --context environment=dev
```

## Platform Contacts

| Need | Contact |
|------|---------|
| Access issues | #platform-team Slack |
| Security concern | #security-team Slack |
| Architecture advice | platform-team office hours (Tues/Thurs 2pm) |
| Incidents | PagerDuty: cap-platform-engineering |
