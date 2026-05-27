"""AWS Config custom rule: deny EC2 instances with IMDSv1 enabled."""
import json
import boto3

CONFIG_CLIENT = boto3.client('config')
EC2_CLIENT = boto3.client('ec2')

def evaluate_compliance(instance):
    metadata_options = instance.get('MetadataOptions', {})
    if metadata_options.get('HttpTokens') == 'required':
        return 'COMPLIANT'
    return 'NON_COMPLIANT'

def lambda_handler(event, context):
    invoking_event = json.loads(event['invokingEvent'])
    configuration_item = invoking_event.get('configurationItem')

    if not configuration_item:
        return

    if configuration_item['resourceType'] != 'AWS::EC2::Instance':
        return

    instance_id = configuration_item['resourceId']

    response = EC2_CLIENT.describe_instances(InstanceIds=[instance_id])
    instances = response['Reservations'][0]['Instances']

    if not instances:
        return

    compliance = evaluate_compliance(instances[0])

    CONFIG_CLIENT.put_evaluations(
        Evaluations=[{
            'ComplianceResourceType': 'AWS::EC2::Instance',
            'ComplianceResourceId': instance_id,
            'ComplianceType': compliance,
            'OrderingTimestamp': configuration_item['configurationItemCaptureTime'],
        }],
        ResultToken=event['resultToken'],
    )
