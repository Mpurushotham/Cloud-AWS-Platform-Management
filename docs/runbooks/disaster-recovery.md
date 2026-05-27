# Disaster Recovery Runbook

## RTO/RPO Targets

| Component | RTO | RPO | Strategy |
|-----------|-----|-----|---------|
| EKS cluster | 1 hour | N/A (stateless) | Rebuild from IaC |
| RDS (prod) | 30 min | 5 min | Multi-AZ failover |
| RDS (staging) | 2 hours | 1 hour | Restore from snapshot |
| S3 data buckets | N/A | N/A | Versioning + replication |
| ElastiCache | 30 min | Accept loss | Rebuild from RDS |
| ALB/API GW | 15 min | N/A | Stateless, redeploy |

## RDS Failover (Multi-AZ)

Automatic failover occurs within 60-120 seconds.
No manual action required. Monitor in CloudWatch:
```
Namespace: AWS/RDS
Metric: ReplicaLag (should drop to 0 after failover)
```

Manual forced failover (for testing):
```bash
aws rds reboot-db-instance \
  --db-instance-identifier cap-prod-rds \
  --force-failover
```

## Cross-Region DR (Prod Only)

For catastrophic regional failure:
1. Enable cross-region RDS read replica promotion
2. Update Route53 failover records to point to DR region
3. Deploy EKS cluster from Terraform in DR region (us-west-2)
4. Restore application secrets from Secrets Manager cross-region replication

## Backup Verification (Monthly)

```bash
# List recent RDS snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier cap-prod-rds \
  --query 'DBSnapshots[?SnapshotCreateTime>`2024-01-01`].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table

# Restore test (run in staging account)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier cap-staging-rds-restore-test \
  --db-snapshot-identifier SNAPSHOT_ID \
  --db-instance-class db.t3.medium
```
