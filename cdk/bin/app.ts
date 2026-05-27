#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { NetworkStack } from '../lib/stacks/network-stack';
import { SecurityStack } from '../lib/stacks/security-stack';
import { PlatformStack } from '../lib/stacks/platform-stack';
import { DataStack } from '../lib/stacks/data-stack';
import { ApiStack } from '../lib/stacks/api-stack';
import { ObservabilityStack } from '../lib/stacks/observability-stack';

const app = new cdk.App();

const environment = app.node.tryGetContext('environment') ?? 'dev';
const envConfig = app.node.tryGetContext('environments')[environment];

if (!envConfig) {
  throw new Error(`Unknown environment: ${environment}. Valid values: dev, staging, prod`);
}

const env: cdk.Environment = {
  account: envConfig.account,
  region: envConfig.region,
};

const stackPrefix = `cap-${environment}`;

// Stack 1: Network (foundational — all others depend on it)
const networkStack = new NetworkStack(app, `${stackPrefix}-network`, {
  env,
  environment,
  config: envConfig,
  stackName: `${stackPrefix}-network`,
  description: `CAP ${environment} — VPC, subnets, VPC endpoints, flow logs`,
});

// Stack 2: Security (KMS keys — all other stacks reference them)
const securityStack = new SecurityStack(app, `${stackPrefix}-security`, {
  env,
  environment,
  config: envConfig,
  stackName: `${stackPrefix}-security`,
  description: `CAP ${environment} — KMS keys per service, Security Hub enablement`,
});
securityStack.addDependency(networkStack);

// Stack 3: Platform (EKS, ECS, ECR, bastion)
const platformStack = new PlatformStack(app, `${stackPrefix}-platform`, {
  env,
  environment,
  config: envConfig,
  vpc: networkStack.vpc,
  privateSubnets: networkStack.privateSubnets,
  isolatedSubnets: networkStack.isolatedSubnets,
  kmsKeyArns: securityStack.kmsKeyArns,
  stackName: `${stackPrefix}-platform`,
  description: `CAP ${environment} — EKS cluster, ECS cluster, ECR repositories`,
});
platformStack.addDependency(securityStack);

// Stack 4: Data (RDS, ElastiCache, S3 data buckets)
const dataStack = new DataStack(app, `${stackPrefix}-data`, {
  env,
  environment,
  config: envConfig,
  vpc: networkStack.vpc,
  isolatedSubnets: networkStack.isolatedSubnets,
  kmsKeyArns: securityStack.kmsKeyArns,
  allowedSecurityGroups: platformStack.workloadSecurityGroups,
  stackName: `${stackPrefix}-data`,
  description: `CAP ${environment} — RDS, ElastiCache, data S3 buckets`,
});
dataStack.addDependency(platformStack);

// Stack 5: API (API Gateway, Lambda, WAF, CloudFront)
const apiStack = new ApiStack(app, `${stackPrefix}-api`, {
  env,
  environment,
  config: envConfig,
  vpc: networkStack.vpc,
  kmsKeyArns: securityStack.kmsKeyArns,
  stackName: `${stackPrefix}-api`,
  description: `CAP ${environment} — API Gateway, WAF, CloudFront distribution`,
});
apiStack.addDependency(securityStack);

// Stack 6: Observability (CloudWatch dashboards, alarms, OpenSearch)
const observabilityStack = new ObservabilityStack(app, `${stackPrefix}-observability`, {
  env,
  environment,
  config: envConfig,
  vpc: networkStack.vpc,
  isolatedSubnets: networkStack.isolatedSubnets,
  kmsKeyArns: securityStack.kmsKeyArns,
  stackName: `${stackPrefix}-observability`,
  description: `CAP ${environment} — CloudWatch dashboards, composite alarms, OpenSearch`,
});
observabilityStack.addDependency(dataStack);
observabilityStack.addDependency(apiStack);

app.synth();
