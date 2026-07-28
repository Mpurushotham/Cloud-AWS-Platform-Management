#!/usr/bin/env bash
#
# Destroys the lab in reverse dependency order.
#
# Layers 01 and 02 hold resources that intentionally refuse to be destroyed:
# the Terraform state bucket, the lock table, and the AWS Organization itself.
# Those are reported at the end rather than forced.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_DIR="$REPO_ROOT/terraform/lab"

# Reverse of the apply order.
LAYERS=(04-workload 03-network 02-bootstrap 01-governance 00-identity)

info() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[33m%s\033[0m\n' "$1"; }

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  warn 'Cannot reach AWS. If you signed in with "aws login", run:'
  warn '  eval "$(aws configure export-credentials --format env)"'
  exit 2
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"

cat <<EOF

This will destroy the cap lab in account $ACCOUNT:

  - the sample API, Lambda function and DynamoDB table (data is lost)
  - the VPC and all networking
  - the GitHub OIDC provider and the four CI roles
  - the OU tree, the Service Control Policies and the CloudTrail trail
  - the cap-platform-admin role and the account password policy

The Terraform state bucket, the lock table and the AWS Organization are
protected by prevent_destroy and will be left in place.

EOF

read -r -p 'Type the account ID to confirm: ' answer
if [[ "$answer" != "$ACCOUNT" ]]; then
  echo 'Account ID did not match. Nothing was destroyed.'
  exit 1
fi

failed=()

for layer in "${LAYERS[@]}"; do
  dir="$LAB_DIR/$layer"
  [[ -d "$dir" ]] || continue

  info "Destroying $layer"

  if [[ ! -f "$dir/terraform.tfstate" && ! -d "$dir/.terraform" ]]; then
    echo 'Not initialised or no state; skipping.'
    continue
  fi

  varfile=()
  [[ -f "$dir/terraform.tfvars" ]] && varfile=(-var-file=terraform.tfvars)

  if ! terraform -chdir="$dir" destroy "${varfile[@]}" -auto-approve; then
    warn "Layer $layer did not destroy cleanly."
    failed+=("$layer")
  fi
done

info 'Remaining protected resources'

cat <<EOF
These survive by design. Remove them by hand only if you are certain:

  # Terraform state bucket (holds the history of every apply)
  aws s3 rm s3://cap-lab-tfstate-$ACCOUNT --recursive
  aws s3api delete-bucket --bucket cap-lab-tfstate-$ACCOUNT

  # State lock table
  aws dynamodb delete-table --table-name cap-lab-terraform-state-lock

  # Audit and access logs
  aws s3 rm s3://cap-lab-cloudtrail-$ACCOUNT  --recursive
  aws s3api delete-bucket --bucket cap-lab-cloudtrail-$ACCOUNT
  aws s3 rm s3://cap-lab-access-logs-$ACCOUNT --recursive
  aws s3api delete-bucket --bucket cap-lab-access-logs-$ACCOUNT

The AWS Organization is never deleted by this script. Deleting an organization
is irreversible and unnecessary — it costs nothing to keep.
EOF

if (( ${#failed[@]} )); then
  warn "\nLayers that failed to destroy: ${failed[*]}"
  warn 'Versioned buckets usually need their object versions removed first.'
  exit 1
fi

info 'Teardown complete'
