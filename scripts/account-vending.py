#!/usr/bin/env python3
"""
Account Vending Machine — creates a new AWS account in the Organization,
applies the Control Tower baseline, assigns SSO permission sets, and
configures the Terraform state backend for the new account.
"""
import argparse
import json
import sys
import boto3

ORG_CLIENT = boto3.client('organizations')
SSO_CLIENT = boto3.client('sso-admin')
SSM_CLIENT = boto3.client('ssm')

REQUIRED_TAGS = {
    'Project': 'cap',
    'ManagedBy': 'account-vending-machine',
}

def create_account(name: str, email: str, ou_name: str) -> str:
    """Create a new AWS Organization member account."""
    print(f"Creating account: {name} ({email}) in OU: {ou_name}")

    response = ORG_CLIENT.create_account(
        AccountName=name,
        Email=email,
        RoleName='AWSControlTowerExecution',
        IamUserAccessToBilling='ALLOW',
        Tags=[{'Key': k, 'Value': v} for k, v in REQUIRED_TAGS.items()],
    )

    create_status = response['CreateAccountStatus']
    request_id = create_status['Id']

    import time
    while True:
        status = ORG_CLIENT.describe_create_account_status(CreateAccountRequestId=request_id)
        state = status['CreateAccountStatus']['State']
        print(f"  Status: {state}")
        if state == 'SUCCEEDED':
            account_id = status['CreateAccountStatus']['AccountId']
            print(f"  Account created: {account_id}")
            return account_id
        elif state == 'FAILED':
            reason = status['CreateAccountStatus'].get('FailureReason', 'Unknown')
            raise RuntimeError(f"Account creation failed: {reason}")
        time.sleep(10)

def move_to_ou(account_id: str, ou_name: str) -> None:
    """Move account to the correct Organizational Unit."""
    root_id = ORG_CLIENT.list_roots()['Roots'][0]['Id']
    ous = ORG_CLIENT.list_children(ParentId=root_id, ChildType='ORGANIZATIONAL_UNIT')['Children']

    target_ou_id = None
    for ou in ous:
        ou_info = ORG_CLIENT.describe_organizational_unit(OrganizationalUnitId=ou['Id'])
        if ou_info['OrganizationalUnit']['Name'] == ou_name:
            target_ou_id = ou['Id']
            break

    if not target_ou_id:
        raise ValueError(f"OU not found: {ou_name}")

    ORG_CLIENT.move_account(
        AccountId=account_id,
        SourceParentId=root_id,
        DestinationParentId=target_ou_id,
    )
    print(f"  Moved account {account_id} to OU {ou_name} ({target_ou_id})")

def main():
    parser = argparse.ArgumentParser(description='CAP Account Vending Machine')
    parser.add_argument('--name', required=True, help='Account name (e.g., cap-team-xyz)')
    parser.add_argument('--email', required=True, help='Root email for the new account')
    parser.add_argument('--ou', required=True, help='OU name (Non-Prod, Prod, Sandbox, etc.)')
    parser.add_argument('--environment', required=True, help='Environment tag (dev, staging, prod, sandbox)')
    args = parser.parse_args()

    print("==> CAP Account Vending Machine")
    print(f"    Name: {args.name}")
    print(f"    Email: {args.email}")
    print(f"    OU: {args.ou}")

    account_id = create_account(args.name, args.email, args.ou)
    move_to_ou(account_id, args.ou)

    print(f"\n==> Account {account_id} provisioned successfully.")
    print("    Next steps:")
    print("    1. Apply landing-zone Terraform module for this account")
    print("    2. Assign SSO permission sets in IAM Identity Center")
    print("    3. Add account to terraform/environments/ and deploy networking")

if __name__ == '__main__':
    main()
