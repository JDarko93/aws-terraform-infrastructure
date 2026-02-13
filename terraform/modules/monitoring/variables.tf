variable "environment" {
  description = "Environment name"
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN suffix for CloudWatch metrics"
  type        = string
}

variable "target_group_arn" {
  description = "Target group ARN suffix for CloudWatch metrics"
  type        = string
}

variable "autoscaling_group_name" {
  description = "Auto Scaling Group name"
  type        = string
}

variable "db_instance_id" {
  description = "RDS instance identifier"
  type        = string
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
}