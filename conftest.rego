package main

import future.keywords.if
import future.keywords.in

# ── S3 Public Access Block ─────────────────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_s3_bucket"
    bucket_name := resource.values.bucket
    not any_block_public_access(resource.address, input)
    msg := sprintf("S3 bucket '%v' must have all four public access block settings enabled", [bucket_name])
}

any_block_public_access(bucket_addr, plan) if {
    resource := plan.planned_values.root_module.resources[_]
    resource.type == "aws_s3_bucket_public_access_block"
    resource.values.bucket == bucket_addr
    resource.values.block_public_acls == true
    resource.values.block_public_policy == true
    resource.values.ignore_public_acls == true
    resource.values.restrict_public_buckets == true
}

# ── EKS Public Endpoint Denied in Prod ────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_eks_cluster"
    resource.values.vpc_config[_].endpoint_public_access == true
    input.variables.environment.value == "prod"
    msg := sprintf("EKS cluster '%v' must disable public endpoint in prod environment", [resource.name])
}

# ── RDS Storage Encryption Required ───────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_db_instance"
    resource.values.storage_encrypted != true
    msg := sprintf("RDS instance '%v' must have storage_encrypted=true", [resource.name])
}

# ── KMS Key Rotation Required ─────────────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_kms_key"
    resource.values.enable_key_rotation != true
    msg := sprintf("KMS key '%v' must have enable_key_rotation=true", [resource.name])
}

# ── IMDSv2 Required on EC2 Instances ─────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_instance"
    metadata := resource.values.metadata_options[_]
    metadata.http_tokens != "required"
    msg := sprintf("EC2 instance '%v' must require IMDSv2 (http_tokens=required)", [resource.name])
}

# ── SQS Queue Encryption Required ────────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_sqs_queue"
    not resource.values.kms_master_key_id
    msg := sprintf("SQS queue '%v' must have KMS encryption (kms_master_key_id)", [resource.name])
}

# ── SNS Topic Encryption Required ────────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_sns_topic"
    not resource.values.kms_master_key_id
    msg := sprintf("SNS topic '%v' must have KMS encryption (kms_master_key_id)", [resource.name])
}

# ── ElastiCache Encryption Required ──────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_elasticache_replication_group"
    resource.values.at_rest_encryption_enabled != true
    msg := sprintf("ElastiCache replication group '%v' must have at_rest_encryption_enabled=true", [resource.name])
}

deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_elasticache_replication_group"
    resource.values.transit_encryption_enabled != true
    msg := sprintf("ElastiCache replication group '%v' must have transit_encryption_enabled=true", [resource.name])
}

# ── VPC Flow Logs Required ────────────────────────────────────────────────────
warn[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_vpc"
    vpc_id := resource.address
    not any_flow_log(vpc_id, input)
    msg := sprintf("VPC '%v' should have flow logs enabled", [resource.name])
}

any_flow_log(vpc_id, plan) if {
    resource := plan.planned_values.root_module.resources[_]
    resource.type == "aws_flow_log"
    resource.values.vpc_id == vpc_id
}

# ── No Default VPC Usage ─────────────────────────────────────────────────────
deny[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_default_vpc"
    msg := "Default VPC must not be used. Remove aws_default_vpc resources and use module vpc instead."
}

# ── CloudWatch Log Group Retention Required ───────────────────────────────────
warn[msg] if {
    resource := input.planned_values.root_module.resources[_]
    resource.type == "aws_cloudwatch_log_group"
    not resource.values.retention_in_days
    msg := sprintf("CloudWatch log group '%v' should have retention_in_days set", [resource.name])
}
