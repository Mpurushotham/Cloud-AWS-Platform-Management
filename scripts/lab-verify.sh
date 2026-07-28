#!/usr/bin/env bash
#
# Verifies the lab deployment and fails if anything billable exists.
#
# Intended to run both locally and in CI (see .github/workflows/10-lab-cost-guard.yml).
# Exit codes: 0 all good, 1 a billable resource was found, 2 a control is missing.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
billable=0
missing=0

pass() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Prints nothing when the query returns no rows. AWS CLI emits "None" for an
# empty --output text on some queries, which must not be mistaken for a result.
q() {
  local out
  out="$(aws "$@" 2>/dev/null)" || return 1
  [[ "$out" == "None" ]] && return 0
  printf '%s' "$out"
}

require_empty() {
  local label="$1"; shift
  local result
  result="$(q "$@")"
  if [[ -z "$result" ]]; then
    pass "$label: none"
  else
    fail "$label: $result"
    billable=1
  fi
}

require_present() {
  local label="$1"; shift
  local result
  result="$(q "$@")"
  if [[ -n "$result" ]]; then
    pass "$label: $result"
  else
    fail "$label: missing"
    missing=1
  fi
}

ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || {
  echo "Cannot reach AWS. If you signed in with 'aws login', run:"
  echo '  eval "$(aws configure export-credentials --format env)"'
  exit 2
}

printf '\033[1mLab verification\033[0m  account=%s region=%s\n' "$ACCOUNT" "$REGION"

section 'Billable resources (all must be empty)'
require_empty 'NAT gateways' ec2 describe-nat-gateways \
  --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text
require_empty 'Elastic IPs' ec2 describe-addresses \
  --query 'Addresses[].PublicIp' --output text
require_empty 'Interface VPC endpoints' ec2 describe-vpc-endpoints \
  --query 'VpcEndpoints[?VpcEndpointType==`Interface`].ServiceName' --output text
require_empty 'EC2 instances' ec2 describe-instances \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' --output text
require_empty 'RDS instances' rds describe-db-instances \
  --query 'DBInstances[].DBInstanceIdentifier' --output text
require_empty 'EKS clusters' eks list-clusters --query 'clusters' --output text
require_empty 'Load balancers' elbv2 describe-load-balancers \
  --query 'LoadBalancers[].LoadBalancerName' --output text
require_empty 'Transit gateways' ec2 describe-transit-gateways \
  --query 'TransitGateways[?State!=`deleted`].TransitGatewayId' --output text
require_empty 'OpenSearch domains' opensearch list-domain-names \
  --query 'DomainNames[].DomainName' --output text

# Customer-managed KMS keys bill $1/month each.
cmk="$(aws kms list-keys --query 'Keys[].KeyId' --output text 2>/dev/null | tr '\t' '\n' \
  | while read -r k; do
      [[ -z "$k" ]] && continue
      mgr="$(aws kms describe-key --key-id "$k" --query 'KeyMetadata.KeyManager' --output text 2>/dev/null)"
      [[ "$mgr" == "CUSTOMER" ]] && printf '%s ' "$k"
    done)"
if [[ -z "${cmk// /}" ]]; then
  pass 'Customer-managed KMS keys: none'
else
  warn "Customer-managed KMS keys: $cmk (\$1/month each)"
fi

section 'Governance controls (all must be present)'
require_present 'Organization' organizations describe-organization \
  --query 'Organization.Id' --output text
require_present 'Organizational units' organizations list-organizational-units-for-parent \
  --parent-id "$(aws organizations list-roots --query 'Roots[0].Id' --output text)" \
  --query 'OrganizationalUnits[].Name' --output text
require_present 'SCPs at root' organizations list-policies-for-target \
  --target-id "$(aws organizations list-roots --query 'Roots[0].Id' --output text)" \
  --filter SERVICE_CONTROL_POLICY --query 'Policies[?starts_with(Name,`cap-`)].Name' --output text
require_present 'CloudTrail logging' cloudtrail get-trail-status \
  --name cap-lab-org-trail --query 'IsLogging' --output text
require_present 'GitHub OIDC provider' iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[0].Arn' --output text
require_present 'CI roles' iam list-roles \
  --query 'Roles[?starts_with(RoleName,`cap-`)].RoleName' --output text
require_present 'Budget' budgets describe-budgets --account-id "$ACCOUNT" \
  --query 'Budgets[].BudgetName' --output text

section 'Account baseline'
require_present 'Password policy' iam get-account-password-policy \
  --query 'PasswordPolicy.MinimumPasswordLength' --output text
require_present 'EBS default encryption' ec2 get-ebs-encryption-by-default \
  --query 'EbsEncryptionByDefault' --output text
require_present 'S3 account public access block' s3control get-public-access-block \
  --account-id "$ACCOUNT" --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text

section 'Root credential status'
# CIS 1.4: the account root user should have no access keys at all.
root_keys="$(aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent' --output text 2>/dev/null)"
if [[ "$root_keys" == "0" ]]; then
  pass 'Root access keys: none (CIS 1.4)'
else
  fail 'Root access keys still exist — see terraform/lab/00-identity/README.md'
  missing=1
fi

section 'Month-to-date spend'
start="$(date -u +%Y-%m-01)"
end="$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d '+1 day' +%Y-%m-%d)"
cost="$(aws ce get-cost-and-usage --time-period "Start=$start,End=$end" \
  --granularity MONTHLY --metrics UnblendedCost \
  --query 'ResultsByTime[0].Total.UnblendedCost.Amount' --output text 2>/dev/null)"
printf '  MTD unblended cost: $%s\n' "${cost:-unknown}"

section 'Result'
if (( billable )); then
  echo 'FAILED — billable resources are present.'
  exit 1
elif (( missing )); then
  echo 'FAILED — one or more expected controls are missing.'
  exit 2
else
  echo 'PASSED — lab is intact and nothing billable is running.'
  exit 0
fi
