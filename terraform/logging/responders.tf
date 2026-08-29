data "archive_file" "responder" {
  type        = "zip"
  source_file = "${path.module}/lambda/responder.py"
  output_path = "${path.module}/lambda/responder.zip"
}

resource "aws_iam_role" "responder" {
  name = "${local.prefix}-responder"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "responder" {
  name = "${local.prefix}-responder"
  role = aws_iam_role.responder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:UpdateAccessKey", "iam:DetachUserPolicy"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:StartQuery", "logs:GetQueryResults"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "responder" {
  function_name    = "${local.prefix}-responder"
  filename         = data.archive_file.responder.output_path
  source_code_hash = data.archive_file.responder.output_base64sha256
  handler          = "responder.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.responder.arn
  timeout          = 30
}

# Let EventBridge (GuardDuty findings) invoke it
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.responder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_findings.arn
}

# Let the CloudWatch alarm reach the Lambda through SNS
resource "aws_sns_topic_subscription" "responder" {
  topic_arn = aws_sns_topic.responders.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.responder.arn
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.responder.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.responders.arn
}

resource "aws_cloudwatch_log_metric_filter" "access_key_created" {
  name           = "${local.prefix}-access-key-created"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ ($.eventName = \"CreateAccessKey\") }"

  metric_transformation {
    name      = "AccessKeyCreated"
    namespace = "PurpleRange"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "access_key_created" {
  alarm_name          = "${local.prefix}-access-key-created"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "AccessKeyCreated"
  namespace           = "PurpleRange"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "An IAM access key was created"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.responders.arn]
}