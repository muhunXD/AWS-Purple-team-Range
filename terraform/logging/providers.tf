provider "aws" {
  region  = var.primary_region
  profile = "mgmt"

  assume_role {
    role_arn = "arn:aws:iam::${var.sandbox_account_id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = {
      Project   = "aws-purple-range"
      ManagedBy = "terraform"
    }
  }
}
