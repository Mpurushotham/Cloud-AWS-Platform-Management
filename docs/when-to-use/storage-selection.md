# When to Use S3 vs RDS vs ElastiCache vs DynamoDB vs EFS

## Quick Decision Table

| Data Type | Access Pattern | Use |
|-----------|---------------|-----|
| Objects, files, media, backups | Read/write by key | S3 |
| Relational data with JOINs | SQL queries, transactions | RDS (PostgreSQL/MySQL) |
| Session state, rate limiting | Low-latency reads, TTL | ElastiCache (Redis) |
| High-throughput key-value | Single-digit ms at any scale | DynamoDB |
| Shared filesystem for containers | POSIX, NFS mount needed | EFS |
| Time-series metrics | Time-ordered queries | CloudWatch / OpenSearch |
| Full-text search, log analysis | Search, aggregations | OpenSearch |

---

## S3 — When to Use It

**Use S3 for:**
- Static assets (images, CSS, JS, HTML)
- Application backups and snapshots
- Data lake storage (raw + processed)
- CloudTrail logs, Config snapshots, VPC flow logs
- Terraform state files
- SBOM and compliance report archival
- Container image layers (via ECR, which is S3-backed)

**Do not use S3 for:**
- Structured data that needs SQL queries (use RDS)
- Low-latency lookups < 10ms (use ElastiCache or DynamoDB)
- File locking or POSIX semantics (use EFS)

**Platform S3 buckets (already provisioned via Terraform module):**
- `cap-{env}-state` — Terraform state (logging account)
- `cap-{env}-audit-logs` — CloudTrail, Config, flow logs (logging account)
- `cap-{env}-app-data` — application data buckets

**Security requirements (non-negotiable):**
```hcl
# All enforced by the s3 Terraform module
block_public_acls       = true
block_public_policy     = true
ignore_public_acls      = true
restrict_public_buckets = true
server_side_encryption  = "aws:kms"  # not AES256
versioning              = true
access_logging          = enabled    # to audit-logs bucket
lifecycle_rules         = [abort_incomplete_multipart, expire_noncurrent_versions]
```

---

## RDS (PostgreSQL/MySQL) — When to Use It

**Use RDS when:**
- Data has relationships (user → orders → line items)
- Need ACID transactions
- Complex queries with JOINs, aggregations, subqueries
- Existing application uses SQL

**Platform RDS configuration by environment:**

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Instance class | db.t3.medium | db.m5.large | db.m5.2xlarge |
| Multi-AZ | No | No | Yes |
| Backup retention | 7 days | 7 days | 35 days |
| Deletion protection | No | No | Yes |
| Enhanced monitoring | 60s | 60s | 60s |
| Performance Insights | 7 days | 7 days | 7 days |

**Accessing RDS from applications:**
```bash
# Never use the master password directly in apps
# Use a dedicated application user with minimal privileges:
CREATE USER app_user WITH PASSWORD 'from-secrets-manager';
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE orders TO app_user;
# Do NOT grant CREATE TABLE or DROP in production
```

**Connection pooling:** Use PgBouncer (ECS sidecar) in prod — RDS max connections is limited by instance size. `db.m5.2xlarge` supports ~3,000 connections but each connection uses ~5MB RAM.

---

## ElastiCache (Redis) — When to Use It

**Use ElastiCache/Redis for:**
- Session storage (web sessions with TTL)
- API rate limiting (sliding window counters)
- Caching expensive database query results
- Pub/sub messaging between services
- Distributed locks (Redlock pattern)
- Leaderboards and sorted sets

**Do not use for:**
- Persistent data — Redis can lose data on restart without persistence enabled
- Data > node memory — Redis is in-memory, no spillover to disk
- Full-text search (use OpenSearch)

**Platform ElastiCache configuration:**
```hcl
# All environments:
engine           = "redis"
engine_version   = "7.x"
node_type        = "cache.t3.medium"   # dev/staging
                   "cache.m5.large"    # prod
cluster_mode     = false               # disabled; use replication_group for HA
at_rest_encryption = true             # KMS
in_transit_encryption = true          # TLS
auth_token       = true               # require AUTH command
```

**Connecting:**
```python
import redis

r = redis.Redis(
    host="cap-dev-redis.xxxxx.cache.amazonaws.com",
    port=6379,
    ssl=True,                         # always TLS
    password=get_secret("cap/dev/payment-api/redis-auth-token"),
    decode_responses=True
)

# Rate limiting example
def is_rate_limited(user_id: str, limit: int = 100, window: int = 60) -> bool:
    key = f"rate:{user_id}:{int(time.time() // window)}"
    count = r.incr(key)
    r.expire(key, window * 2)
    return count > limit
```

---

## DynamoDB — When to Use It

**Use DynamoDB when:**
- Need single-digit millisecond latency at any scale
- Access pattern is always by partition key (no JOINs needed)
- Unpredictable or very high throughput (DynamoDB autoscales)
- Global tables needed (multi-region active-active)
- Serverless / Lambda workloads (no connection pool management)

**Do not use DynamoDB when:**
- Need SQL queries, JOINs, or complex aggregations
- Team is not familiar with NoSQL access pattern design
- Data model is still evolving — schema changes are hard in DynamoDB

**Good DynamoDB use cases in this platform:**
- Feature flags table (partition key: `feature_name`)
- Terraform state locking (partition key: `LockID`) — already used in bootstrap
- Event sourcing (partition key: `aggregate_id`, sort key: `event_timestamp`)
- User preferences (partition key: `user_id`)

**Platform DynamoDB table requirements:**
```hcl
billing_mode        = "PAY_PER_REQUEST"   # on-demand, not provisioned
point_in_time_recovery = true
server_side_encryption = true             # KMS
stream_enabled      = true                # for event-driven patterns
ttl_enabled         = true                # for expiring records
```

---

## EFS — When to Use It

**Use EFS when:**
- Multiple containers need to share a POSIX filesystem simultaneously
- Application requires file locking semantics
- Migrating a legacy app that writes to local disk

**Do not use EFS when:**
- You just need object storage — use S3 (10× cheaper)
- Low-latency required — EFS latency is higher than local disk
- Running Lambda — EFS access adds cold start latency

**EFS is not pre-provisioned by the platform.** If you need it, add it to your CDK stack:
```typescript
const fs = new efs.FileSystem(this, "SharedStorage", {
  vpc,
  encrypted: true,
  kmsKey: props.kmsKey,
  performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
  throughputMode: efs.ThroughputMode.BURSTING,
  removalPolicy: RemovalPolicy.RETAIN,
});
```

---

## OpenSearch — When to Use It

**Use OpenSearch when:**
- Full-text search across large document sets
- Log analysis and aggregation (Kibana-style dashboards)
- Geospatial queries
- Complex analytics that CloudWatch Insights can't handle

**Platform OpenSearch cluster:**
- `cap-{env}-opensearch` — receives VPC flow logs + application logs from Kinesis Firehose
- Access via Kibana proxy through bastion host or VPN

---

## Cost Comparison (approximate, us-east-1, smallest viable option)

| Service | Smallest Viable | Monthly Cost |
|---------|---------------|-------------|
| S3 | 100 GB | ~$2.30 |
| RDS PostgreSQL | db.t3.medium Multi-AZ | ~$95 |
| ElastiCache Redis | cache.t3.micro | ~$25 |
| DynamoDB | PAY_PER_REQUEST, 1M reads | ~$0.25 |
| EFS | 100 GB | ~$30 |
| OpenSearch | t3.medium.search × 1 | ~$55 |

Use `infracost` to get environment-specific estimates before provisioning.
