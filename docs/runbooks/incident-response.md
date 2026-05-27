# Incident Response Runbook

## Severity Levels

| Severity | Definition | Response Time | Escalation |
|----------|-----------|---------------|-----------|
| P1 | Production down, data breach | 15 min | On-call + Manager |
| P2 | Significant degradation, security finding | 1 hour | On-call |
| P3 | Non-critical issue | 4 hours | Team channel |
| P4 | Low-impact, cosmetic | Next business day | Ticket |

## GuardDuty HIGH/CRITICAL Finding Response

1. **Acknowledge** the finding in Security Hub (`Workflow Status → In Progress`)
2. **Identify** the affected resource from finding detail (instance ID, role ARN, etc.)
3. **Isolate** (if credential compromise suspected):
   ```bash
   # Revoke all active sessions for the IAM role
   aws iam put-role-policy --role-name ROLE_NAME \
     --policy-name EmergencyDeny \
     --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'
   ```
4. **Investigate** using CloudTrail Athena queries:
   ```sql
   SELECT eventtime, eventsource, eventname, sourceipaddress, useridentity
   FROM cloudtrail_logs
   WHERE useridentity.arn LIKE '%ROLE_NAME%'
   AND eventtime > '2024-01-01T00:00:00Z'
   ORDER BY eventtime DESC LIMIT 100;
   ```
5. **Eradicate**: Rotate credentials, patch vulnerability, update SCPs
6. **Recover**: Restore from backup if needed, verify workload integrity
7. **Post-mortem**: Document in incident ticket, update runbook

## Security Hub CRITICAL Finding Response

1. Navigate to Security Hub → Findings → filter by severity: CRITICAL
2. Assign finding to engineer (`Assigned to → your IAM user`)
3. Review remediation guidance in finding detail
4. Apply fix (Terraform PR or manual remediation)
5. Re-evaluate: Config rule will re-evaluate within 24h or trigger manually
6. Update finding status to RESOLVED with note

## Production Terraform Apply Emergency Rollback

```bash
# Identify previous good state
git log --oneline terraform/environments/prod/ | head -20

# Roll back to previous commit
git revert HEAD --no-edit
git push origin main
# 08-terraform-apply.yml triggers automatically
```
