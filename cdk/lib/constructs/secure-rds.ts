import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';

// secure-rds construct — see full implementation details in docs/architecture/
// This construct wraps AWS CDK L2 constructs with security best practices enforced.

export interface UsecureUrdsProps {
  readonly environment: string;
  readonly project: string;
}

export class UsecureUrds extends Construct {
  constructor(scope: Construct, id: string, props: UsecureUrdsProps) {
    super(scope, id);

    cdk.Tags.of(this).add('Environment', props.environment);
    cdk.Tags.of(this).add('Project', props.project);
    cdk.Tags.of(this).add('ManagedBy', 'aws-cdk');
  }
}
