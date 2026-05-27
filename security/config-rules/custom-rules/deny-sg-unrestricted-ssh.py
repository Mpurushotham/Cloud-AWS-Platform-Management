"""AWS Config custom rule: security groups must not allow 0.0.0.0/0 on port 22."""
import json
import boto3

CONFIG_CLIENT = boto3.client('config')

def is_compliant(sg_config):
    ip_permissions = sg_config.get('ipPermissions', [])
    for perm in ip_permissions:
        if perm.get('fromPort') == 22 or perm.get('toPort') == 22 or perm.get('ipProtocol') == '-1':
            ip_ranges = perm.get('ipRanges', [])
            ipv6_ranges = perm.get('ipv6Ranges', [])
            for ip_range in ip_ranges:
                if ip_range.get('cidrIp') in ('0.0.0.0/0',):
                    return False
            for ipv6_range in ipv6_ranges:
                if ipv6_range.get('cidrIpv6') == '::/0':
                    return False
    return True

def lambda_handler(event, context):
    invoking_event = json.loads(event['invokingEvent'])
    configuration_item = invoking_event.get('configurationItem')

    if not configuration_item or configuration_item['resourceType'] != 'AWS::EC2::SecurityGroup':
        return

    sg_config = configuration_item.get('configuration', {})
    compliance = 'COMPLIANT' if is_compliant(sg_config) else 'NON_COMPLIANT'

    CONFIG_CLIENT.put_evaluations(
        Evaluations=[{
            'ComplianceResourceType': 'AWS::EC2::SecurityGroup',
            'ComplianceResourceId': configuration_item['resourceId'],
            'ComplianceType': compliance,
            'OrderingTimestamp': configuration_item['configurationItemCaptureTime'],
        }],
        ResultToken=event['resultToken'],
    )
