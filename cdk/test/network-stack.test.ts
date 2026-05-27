import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../lib/stacks/network-stack';

const devConfig = {
  account: '444444444444',
  region: 'us-east-1',
  vpcCidr: '10.10.0.0/16',
  maxAzs: 3,
  removalPolicy: 'DESTROY',
  logRetentionDays: 30,
};

function buildStack() {
  const app = new cdk.App();
  return new NetworkStack(app, 'TestNetworkStack', {
    env: { account: '444444444444', region: 'us-east-1' },
    environment: 'dev',
    config: devConfig,
  });
}

test('VPC is created', () => {
  const template = Template.fromStack(buildStack());
  template.hasResource('AWS::EC2::VPC', {});
});

test('VPC has DNS hostnames enabled', () => {
  const template = Template.fromStack(buildStack());
  template.hasResourceProperties('AWS::EC2::VPC', {
    EnableDnsHostnames: true,
    EnableDnsSupport: true,
  });
});

test('VPC flow logs are enabled', () => {
  const template = Template.fromStack(buildStack());
  template.hasResource('AWS::EC2::FlowLog', {});
});

test('VPC flow logs go to CloudWatch Logs', () => {
  const template = Template.fromStack(buildStack());
  template.hasResourceProperties('AWS::EC2::FlowLog', {
    LogDestinationType: 'cloud-watch-logs',
    TrafficType: 'ALL',
  });
});

test('S3 gateway endpoint exists', () => {
  const template = Template.fromStack(buildStack());
  template.hasResourceProperties('AWS::EC2::VPCEndpoint', {
    VpcEndpointType: 'Gateway',
    ServiceName: Match.stringLikeRegexp('s3'),
  });
});

test('Interface endpoints exist for critical services', () => {
  const template = Template.fromStack(buildStack());
  const endpoints = template.findResources('AWS::EC2::VPCEndpoint', {
    Properties: { VpcEndpointType: 'Interface' },
  });
  expect(Object.keys(endpoints).length).toBeGreaterThan(5);
});

test('Public subnets do not auto-assign public IPs', () => {
  const template = Template.fromStack(buildStack());
  const publicSubnets = template.findResources('AWS::EC2::Subnet', {
    Properties: { MapPublicIpOnLaunch: true },
  });
  expect(Object.keys(publicSubnets).length).toBe(0);
});
