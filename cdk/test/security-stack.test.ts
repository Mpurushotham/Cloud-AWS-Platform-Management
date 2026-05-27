import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { SecurityStack } from '../lib/stacks/security-stack';

function buildStack(environment = 'dev') {
  const app = new cdk.App();
  return new SecurityStack(app, 'TestSecurityStack', {
    env: { account: '444444444444', region: 'us-east-1' },
    environment,
    config: {},
  });
}

test('KMS keys are created for all services', () => {
  const template = Template.fromStack(buildStack());
  const keys = template.findResources('AWS::KMS::Key', {});
  expect(Object.keys(keys).length).toBeGreaterThanOrEqual(11);
});

test('All KMS keys have rotation enabled', () => {
  const template = Template.fromStack(buildStack());
  template.allResourcesProperties('AWS::KMS::Key', {
    EnableKeyRotation: true,
  });
});

test('Prod KMS keys have long deletion window', () => {
  const prodStack = buildStack('prod');
  const template = Template.fromStack(prodStack);
  const keys = template.findResources('AWS::KMS::Key', {
    Properties: { PendingWindowInDays: 30 },
  });
  expect(Object.keys(keys).length).toBeGreaterThan(0);
});
