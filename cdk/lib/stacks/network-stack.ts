import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import { SecureVpcConstruct } from '../constructs/secure-vpc';

export interface NetworkStackProps extends cdk.StackProps {
  readonly environment: string;
  readonly config: Record<string, any>;
}

export class NetworkStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly privateSubnets: ec2.ISubnet[];
  public readonly publicSubnets: ec2.ISubnet[];
  public readonly isolatedSubnets: ec2.ISubnet[];

  constructor(scope: Construct, id: string, props: NetworkStackProps) {
    super(scope, id, props);

    const { environment, config } = props;

    const flowLogKey = new kms.Key(this, 'FlowLogKey', {
      alias: `cap/${environment}/kms/flow-logs`,
      description: `KMS key for VPC flow log encryption — ${environment}`,
      enableKeyRotation: true,
      removalPolicy: environment === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    const secureVpc = new SecureVpcConstruct(this, 'Vpc', {
      environment,
      project: 'cap',
      vpcCidr: config.vpcCidr as string,
      maxAzs: (config.maxAzs as number) ?? 3,
      natGateways: (config.maxAzs as number) ?? 3,
      flowLogKey,
      flowLogRetentionDays: environment === 'prod' ? logs.RetentionDays.ONE_YEAR : logs.RetentionDays.ONE_MONTH,
      enableEndpoints: true,
    });

    this.vpc = secureVpc.vpc;
    this.privateSubnets = secureVpc.privateSubnets;
    this.publicSubnets = secureVpc.publicSubnets;
    this.isolatedSubnets = secureVpc.isolatedSubnets;

    new cdk.CfnOutput(this, 'VpcId', { value: this.vpc.vpcId, exportName: `cap-${environment}-vpc-id` });
    new cdk.CfnOutput(this, 'PrivateSubnetIds', {
      value: cdk.Fn.join(',', this.privateSubnets.map(s => s.subnetId)),
      exportName: `cap-${environment}-private-subnet-ids`,
    });

    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', 'cap');
    cdk.Tags.of(this).add('ManagedBy', 'aws-cdk');
  }
}
