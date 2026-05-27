import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

export interface ObservabilityConstructProps {
  readonly environment: string;
  readonly project: string;
  readonly alarmEncryptionKey: kms.IKey;
  readonly alertEmailEndpoint?: string;
}

export class ObservabilityConstruct extends Construct {
  public readonly alarmTopic: sns.Topic;
  public readonly securityAlarm: cloudwatch.CompositeAlarm;

  constructor(scope: Construct, id: string, props: ObservabilityConstructProps) {
    super(scope, id);

    const { environment, project, alarmEncryptionKey, alertEmailEndpoint } = props;

    // ── SNS Alert Topic ──────────────────────────────────────────────────────
    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `${project}-${environment}-platform-alarms`,
      masterKey: alarmEncryptionKey,
      displayName: `CAP ${environment} Platform Alarms`,
    });

    if (alertEmailEndpoint) {
      new sns.Subscription(this, 'EmailSubscription', {
        topic: this.alarmTopic,
        protocol: sns.SubscriptionProtocol.EMAIL,
        endpoint: alertEmailEndpoint,
      });
    }

    // ── Security Metric Alarms ───────────────────────────────────────────────
    const unauthorizedApiAlarm = new cloudwatch.Alarm(this, 'UnauthorizedApiAlarm', {
      alarmName: `${project}-${environment}-unauthorized-api-calls`,
      alarmDescription: 'Alert on unauthorized API calls (potential credential compromise)',
      metric: new cloudwatch.Metric({
        namespace: 'CloudTrailMetrics',
        metricName: 'UnauthorizedAttemptCount',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const rootLoginAlarm = new cloudwatch.Alarm(this, 'RootLoginAlarm', {
      alarmName: `${project}-${environment}-root-login`,
      alarmDescription: 'Alert on any root account login',
      metric: new cloudwatch.Metric({
        namespace: 'CloudTrailMetrics',
        metricName: 'RootAccountUsageCount',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const sgChangesAlarm = new cloudwatch.Alarm(this, 'SecurityGroupChangesAlarm', {
      alarmName: `${project}-${environment}-security-group-changes`,
      alarmDescription: 'Alert on unexpected security group modifications',
      metric: new cloudwatch.Metric({
        namespace: 'CloudTrailMetrics',
        metricName: 'SecurityGroupEventCount',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // ── Composite Security Alarm ─────────────────────────────────────────────
    this.securityAlarm = new cloudwatch.CompositeAlarm(this, 'SecurityCompositeAlarm', {
      compositeAlarmName: `${project}-${environment}-security-composite`,
      alarmDescription: 'Composite security alarm — any of: unauthorized API, root login, SG change',
      alarmRule: cloudwatch.AlarmRule.anyOf(
        cloudwatch.AlarmRule.fromAlarm(unauthorizedApiAlarm, cloudwatch.AlarmState.ALARM),
        cloudwatch.AlarmRule.fromAlarm(rootLoginAlarm, cloudwatch.AlarmState.ALARM),
        cloudwatch.AlarmRule.fromAlarm(sgChangesAlarm, cloudwatch.AlarmState.ALARM)
      ),
    });

    new cloudwatch.CfnCompositeAlarm(this, 'SecurityAlarmAction', {
      alarmName: this.securityAlarm.alarmName,
      alarmActions: [this.alarmTopic.topicArn],
    } as any);

    // ── Platform Dashboard ───────────────────────────────────────────────────
    new cloudwatch.Dashboard(this, 'PlatformDashboard', {
      dashboardName: `${project}-${environment}-platform-overview`,
      widgets: [
        [new cloudwatch.TextWidget({
          markdown: `## CAP ${environment.toUpperCase()} Platform Overview\n*Last updated: Auto-refresh*`,
          width: 24,
          height: 2,
        })],
        [
          new cloudwatch.AlarmWidget({
            title: 'Security Composite Alarm',
            alarm: this.securityAlarm,
            width: 6,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'Unauthorized API Calls',
            left: [unauthorizedApiAlarm.metric],
            width: 9,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'SG Changes',
            left: [sgChangesAlarm.metric],
            width: 9,
            height: 6,
          }),
        ],
      ],
    });

    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', project);
    cdk.Tags.of(this).add('ManagedBy', 'aws-cdk');
  }
}
