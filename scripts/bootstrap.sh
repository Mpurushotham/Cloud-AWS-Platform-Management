#!/usr/bin/env bash
set -euo pipefail

echo "==> CAP Bootstrap: Installing required tools"

# Check OS
OS=$(uname -s)

if [[ "$OS" == "Darwin" ]]; then
  which brew || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
  brew install terraform awscli node pre-commit tflint checkov jq git
elif [[ "$OS" == "Linux" ]]; then
  sudo apt-get update -y
  sudo apt-get install -y curl git jq unzip
  # Terraform
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update && sudo apt-get install -y terraform
  # Node.js
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

# Install pre-commit hooks
pre-commit install --install-hooks
pre-commit install --hook-type commit-msg

# Install CDK dependencies
cd cdk && npm ci && cd ..

# Install commitlint
npm install --save-dev @commitlint/cli @commitlint/config-conventional

echo "==> Bootstrap complete. See CLAUDE.md for next steps."
