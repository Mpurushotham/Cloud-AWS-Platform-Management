import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

export interface UplatformUstackProps extends cdk.StackProps {
  readonly environment: string;
  readonly config: Record<string, unknown>;
  readonly vpc?: ec2.IVpc;
  readonly privateSubnets?: ec2.ISubnet[];
  readonly isolatedSubnets?: ec2.ISubnet[];
  readonly kmsKeyArns?: Record<string, string>;
  readonly workloadSecurityGroups?: ec2.ISecurityGroup[];
  readonly allowedSecurityGroups?: ec2.ISecurityGroup[];
}

export class UplatformUstack extends cdk.Stack {
  // Public properties exported for dependent stacks
  public readonly vpc!: ec2.IVpc;
  public readonly privateSubnets!: ec2.ISubnet[];
  public readonly isolatedSubnets!: ec2.ISubnet[];
  public readonly kmsKeyArns!: Record<string, string>;
  public readonly workloadSecurityGroups!: ec2.ISecurityGroup[];

  constructor(scope: Construct, id: string, props: UplatformUstackProps) {
    super(scope, id, props);

    const { environment } = props;

    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', 'cap');
    cdk.Tags.of(this).add('ManagedBy', 'aws-cdk');
    cdk.Tags.of(this).add('Stack', 'platform-stack');
  }
}
