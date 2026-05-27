#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENTS=("dev" "staging" "prod")
DRIFT_FOUND=0

for env in "${ENVIRONMENTS[@]}"; do
  echo "==> Checking drift in ${env}..."
  cd "terraform/environments/${env}"

  terraform init -input=false -no-color > /dev/null

  if ! terraform plan -var-file=terraform.tfvars -detailed-exitcode -input=false -no-color; then
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]]; then
      echo "DRIFT DETECTED in ${env}"
      DRIFT_FOUND=1
    elif [[ $EXIT_CODE -eq 1 ]]; then
      echo "ERROR running plan in ${env}"
      DRIFT_FOUND=1
    fi
  else
    echo "No drift in ${env}"
  fi

  cd - > /dev/null
done

if [[ $DRIFT_FOUND -eq 1 ]]; then
  echo ""
  echo "==> DRIFT DETECTED in one or more environments. Review plan output above."
  exit 1
else
  echo "==> All environments clean — no drift detected."
fi
