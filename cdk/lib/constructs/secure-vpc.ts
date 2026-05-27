import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

export interface SecureVpcProps {
  readonly environment: string;
  readonly project: string;
  readonly vpcCidr: string;
  readonly maxAzs?: number;
  readonly natGateways?: number;
  readonly flowLogRetentionDays?: logs.RetentionDays;
  readonly flowLogKey: kms.IKey;
  readonly enableEndpoints?: boolean;
}

export class SecureVpcConstruct extends Construct {
  public readonly vpc: ec2.Vpc;
  public readonly privateSubnets: ec2.ISubnet[];
  public readonly publicSubnets: ec2.ISubnet[];
  public readonly isolatedSubnets: ec2.ISubnet[];
  public readonly vpcEndpoints: Record<string, ec2.InterfaceVpcEndpoint>;

  constructor(scope: Construct, id: string, props: SecureVpcProps) {
    super(scope, id);

    const {
      environment,
      project,
      vpcCidr,
      maxAzs = 3,
      natGateways = maxAzs,
      flowLogRetentionDays = logs.RetentionDays.ONE_YEAR,
      flowLogKey,
      enableEndpoints = true,
    } = props;

    // ── Flow Log Group ──────────────────────────────────────────────────────
    const flowLogGroup = new logs.LogGroup(this, 'VpcFlowLogs', {
      logGroupName: `/aws/vpc/${project}-${environment}/flow-logs`,
      retention: flowLogRetentionDays,
      encryptionKey: flowLogKey,
      removalPolicy: environment === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    // ── VPC ─────────────────────────────────────────────────────────────────
    this.vpc = new ec2.Vpc(this, 'Vpc', {
      vpcName: `${project}-${environment}-vpc`,
      ipAddresses: ec2.IpAddresses.cidr(vpcCidr),
      maxAzs,
      natGateways,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          mapPublicIpOnLaunch: false,
        },
        {
          cidrMask: 22,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'Isolated',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      restrictDefaultSecurityGroup: true,
      flowLogs: {
        'vpc-flow-logs': {
          destination: ec2.FlowLogDestination.toCloudWatchLogs(flowLogGroup),
          trafficType: ec2.FlowLogTrafficType.ALL,
        },
      },
    });

    this.privateSubnets = this.vpc.privateSubnets;
    this.publicSubnets = this.vpc.publicSubnets;
    this.isolatedSubnets = this.vpc.isolatedSubnets;

    // ── VPC Endpoints ───────────────────────────────────────────────────────
    this.vpcEndpoints = {};

    if (enableEndpoints) {
      this.vpc.addGatewayEndpoint('S3Endpoint', {
        service: ec2.GatewayVpcEndpointAwsService.S3,
        subnets: [
          { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
          { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
        ],
      });

      this.vpc.addGatewayEndpoint('DynamoDBEndpoint', {
        service: ec2.GatewayVpcEndpointAwsService.DYNAMODB,
      });

      const endpointSg = new ec2.SecurityGroup(this, 'EndpointSg', {
        vpc: this.vpc,
        securityGroupName: `${project}-${environment}-vpc-endpoints-sg`,
        description: 'Allow HTTPS from within VPC to interface endpoints',
        allowAllOutbound: false,
      });
      endpointSg.addIngressRule(
        ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
        ec2.Port.tcp(443),
        'Allow HTTPS from VPC CIDR'
      );

      const interfaceEndpoints: Record<string, ec2.InterfaceVpcEndpointAwsService> = {
        EcrApi: ec2.InterfaceVpcEndpointAwsService.ECR,
        EcrDkr: ec2.InterfaceVpcEndpointAwsService.ECR_DOCKER,
        Ssm: ec2.InterfaceVpcEndpointAwsService.SSM,
        SsmMessages: ec2.InterfaceVpcEndpointAwsService.SSM_MESSAGES,
        Ec2Messages: ec2.InterfaceVpcEndpointAwsService.EC2_MESSAGES,
        SecretsManager: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
        Sts: ec2.InterfaceVpcEndpointAwsService.STS,
        CloudWatchLogs: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
        Kms: ec2.InterfaceVpcEndpointAwsService.KMS,
        Xray: ec2.InterfaceVpcEndpointAwsService.XRAY,
      };

      for (const [name, service] of Object.entries(interfaceEndpoints)) {
        this.vpcEndpoints[name] = this.vpc.addInterfaceEndpoint(`${name}Endpoint`, {
          service,
          subnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
          securityGroups: [endpointSg],
          privateDnsEnabled: true,
        });
      }
    }

    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', project);
    cdk.Tags.of(this).add('ManagedBy', 'aws-cdk');
  }
}
