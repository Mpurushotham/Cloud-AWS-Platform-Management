import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

export interface SecureS3BucketProps {
  readonly bucketName: string;
  readonly environment: string;
  readonly encryptionKey: kms.IKey;
  readonly versioned?: boolean;
  readonly lifecycleRules?: s3.LifecycleRule[];
  readonly serverAccessLogsBucket?: s3.IBucket;
  readonly removalPolicy?: cdk.RemovalPolicy;
  readonly autoDeleteObjects?: boolean;
}

export class SecureS3Bucket extends Construct {
  public readonly bucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: SecureS3BucketProps) {
    super(scope, id);

    const removalPolicy = props.removalPolicy ??
      (props.environment === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY);

    this.bucket = new s3.Bucket(this, 'Bucket', {
      bucketName: props.bucketName,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: props.encryptionKey,
      bucketKeyEnabled: true,

      versioned: props.versioned ?? true,

      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      publicReadAccess: false,

      enforceSSL: true,

      serverAccessLogsBucket: props.serverAccessLogsBucket,
      serverAccessLogsPrefix: props.serverAccessLogsBucket ? `${props.bucketName}/` : undefined,

      lifecycleRules: props.lifecycleRules ?? [
        {
          id: 'abort-incomplete-multipart',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
          enabled: true,
        },
        {
          id: 'noncurrent-version-expiry',
          noncurrentVersionExpiration: cdk.Duration.days(90),
          enabled: true,
        },
      ],

      removalPolicy,
      autoDeleteObjects: removalPolicy === cdk.RemovalPolicy.DESTROY && (props.autoDeleteObjects ?? false),

      objectOwnership: s3.ObjectOwnership.BUCKET_OWNER_ENFORCED,
    });

    cdk.Tags.of(this.bucket).add('Environment', props.environment);
    cdk.Tags.of(this.bucket).add('ManagedBy', 'aws-cdk');
  }
}
