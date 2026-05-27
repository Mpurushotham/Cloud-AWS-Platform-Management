import * as cdk from 'aws-cdk-lib';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

const KMS_SERVICES = ['s3','rds','eks','ecr','cloudtrail','ssm','sns','cloudwatch','guardduty','config','ecs'];

export interface SecurityStackProps extends cdk.StackProps {
  readonly environment: string;
  readonly config: Record<string, any>;
}

export class SecurityStack extends cdk.Stack {
  public readonly kmsKeyArns: Record<string, string>;
  public readonly kmsKeys: Record<string, kms.Key>;

  constructor(scope: Construct, id: string, props: SecurityStackProps) {
    super(scope, id, props);

    const { environment } = props;
    const isProd = environment === 'prod';

    this.kmsKeys = {};
    this.kmsKeyArns = {};

    for (const service of KMS_SERVICES) {
      const key = new kms.Key(this, `KmsKey${service.charAt(0).toUpperCase() + service.slice(1)}`, {
        alias: `cap/${environment}/kms/${service}`,
        description: `KMS key for cap-${environment} ${service}`,
        enableKeyRotation: true,
        removalPolicy: isProd ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      });
      this.kmsKeys[service] = key;
      this.kmsKeyArns[service] = key.keyArn;
      new cdk.CfnOutput(this, `KmsKeyArn${service}`, {
        value: key.keyArn,
        exportName: `cap-${environment}-kms-${service}-arn`,
      });
    }

    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', 'cap');
    cdk.Tags.of(this).add('ManagedBy', 'aws-cdk');
  }
}
