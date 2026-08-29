variable "sandbox_account_id" {
  description = "Account ID of the sandbox account hosting the range"
  type        = string
}

variable "primary_region" {
  description = "Region for all range resources. Must be in the landing zone's allowed_regions."
  type        = string
  default     = "ap-southeast-7"
}