locals {
  prefix = "range"
  allowed_regions = ["ap-southeast-7"]
  log_retention_days = 7 
}

locals {
  trail_arn = "arn:aws:cloudtrail:${var.primary_region}:${var.sandbox_account_id}:trail/${local.prefix}-trail"
}