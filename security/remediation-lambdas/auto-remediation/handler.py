"""
Auto-remediation handler dispatching on AWS Config finding types.
Triggered by EventBridge rule on Config NON_COMPLIANT findings.
"""
import json
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

EC2_CLIENT = boto3.client('ec2')
S3_CLIENT = boto3.client('s3')

REMEDIATION_MAP = {
    'restricted-ssh': remediate_unrestricted_ssh,
    'ec2-imdsv2-check': remediate_imdsv1,
    's3-bucket-public-read-prohibited': remediate_public_s3,
}

def remediate_unrestricted_ssh(resource_id: str) -> None:
    """Remove unrestricted SSH (port 22, 0.0.0.0/0) from security group."""
    try:
        EC2_CLIENT.revoke_security_group_ingress(
            GroupId=resource_id,
            IpPermissions=[{
                'IpProtocol': 'tcp',
                'FromPort': 22,
                'ToPort': 22,
                'IpRanges': [{'CidrIp': '0.0.0.0/0'}],
            }],
        )
        logger.info("Remediated unrestricted SSH on SG %s", resource_id)
    except Exception as exc:
        logger.error("Failed to remediate SG %s: %s", resource_id, exc)

def remediate_imdsv1(resource_id: str) -> None:
    """Enforce IMDSv2 on EC2 instance."""
    try:
        EC2_CLIENT.modify_instance_metadata_options(
            InstanceId=resource_id,
            HttpTokens='required',
            HttpEndpoint='enabled',
        )
        logger.info("Enforced IMDSv2 on instance %s", resource_id)
    except Exception as exc:
        logger.error("Failed to enforce IMDSv2 on %s: %s", resource_id, exc)

def remediate_public_s3(resource_id: str) -> None:
    """Block public access on S3 bucket."""
    try:
        S3_CLIENT.put_public_access_block(
            Bucket=resource_id,
            PublicAccessBlockConfiguration={
                'BlockPublicAcls': True,
                'IgnorePublicAcls': True,
                'BlockPublicPolicy': True,
                'RestrictPublicBuckets': True,
            },
        )
        logger.info("Blocked public access on S3 bucket %s", resource_id)
    except Exception as exc:
        logger.error("Failed to remediate S3 bucket %s: %s", resource_id, exc)

def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    detail = event.get('detail', {})
    config_rule_name = detail.get('configRuleName', '')
    resource_id = detail.get('resourceId', '')
    new_status = detail.get('newEvaluationResult', {}).get('complianceType', '')

    if new_status != 'NON_COMPLIANT':
        logger.info("Ignoring non-NON_COMPLIANT event")
        return

    for rule_pattern, handler_fn in REMEDIATION_MAP.items():
        if rule_pattern in config_rule_name:
            logger.info("Dispatching remediation for rule %s, resource %s", config_rule_name, resource_id)
            handler_fn(resource_id)
            return

    logger.warning("No remediation handler found for rule: %s", config_rule_name)
