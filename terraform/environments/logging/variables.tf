variable "aws_region" { description = "AWS region"; type = string; default = "us-east-1" }
variable "logging_account_id" { description = "Logging account ID"; type = string }
variable "cost_center" { description = "Cost center tag"; type = string }
variable "config_sns_topic_arn" { description = "SNS topic ARN for Config notifications"; type = string }
