resource "aws_s3_bucket" "trail" {
  bucket        = "${local.prefix}-cloudtrail-${var.sandbox_account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-range-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 14
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${var.sandbox_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${local.prefix}"
  retention_in_days = local.log_retention_days
}


resource "aws_iam_role" "cloudtrail_cwl" {
  name = "${local.prefix}-cloudtrail-to-cwl"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cwl" {
  name = "${local.prefix}-cloudtrail-to-cwl"
  role = aws_iam_role.cloudtrail_cwl.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "range" {
  name                          = "${local.prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.trail.id
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cwl.arn
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [
    aws_s3_bucket_policy.trail,
    aws_iam_role_policy.cloudtrail_cwl,
  ]
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.trail.name
}

# ── T1562.008 — CloudTrail tampering ──
resource "aws_cloudwatch_log_metric_filter" "cloudtrail_tampering" {
  name           = "${local.prefix}-cloudtrail-tampering"
  log_group_name = aws_cloudwatch_log_group.trail.name

  pattern = "{ ($.eventName = \"StopLogging\") || ($.eventName = \"DeleteTrail\") || ($.eventName = \"UpdateTrail\") || ($.eventName = \"PutEventSelectors\") }"

  metric_transformation {
    name      = "CloudTrailTamperingAttempts"
    namespace = "PurpleRange"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_tampering" {
  alarm_name          = "${local.prefix}-cloudtrail-tampering"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CloudTrailTamperingAttempts"
  namespace           = "PurpleRange"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Someone tried to stop, delete or reconfigure a CloudTrail trail"
  treat_missing_data  = "notBreaching"
  alarm_actions = [aws_sns_topic.responders.arn]
}

# ── T1552.005 — Instance credential use off-instance ──
resource "aws_cloudwatch_log_metric_filter" "instance_cred_theft" {
  name           = "${local.prefix}-instance-cred-theft"
  log_group_name = aws_cloudwatch_log_group.trail.name

  # Instance-role session (ARN contains i-) whose call did NOT come from inside AWS
  pattern = "{ ($.userIdentity.arn = \"*assumed-role*i-*\") && ($.sourceIPAddress != \"*.amazonaws.com\") }"

  metric_transformation {
    name      = "InstanceCredentialOffInstanceUse"
    namespace = "PurpleRange"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "instance_cred_theft" {
  alarm_name          = "${local.prefix}-instance-cred-theft"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "InstanceCredentialOffInstanceUse"
  namespace           = "PurpleRange"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "EC2 instance role credentials used from a non-AWS IP"
  treat_missing_data  = "notBreaching"
  alarm_actions = [aws_sns_topic.responders.arn]
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${local.prefix}-guardduty-findings"
  description = "Route GuardDuty findings to the responder Lambda"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]  # Medium and above
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "responder"
  arn       = aws_lambda_function.responder.arn 
}

resource "aws_sns_topic" "responders" {
  name = "${local.prefix}-responders"
}