variable "aws_account_id" {
  description = "The AWS account ID"
  type        = string
}

variable "github_oauth_token" {
  description = "The GitHub OAuth token"
  type        = string
  sensitive   = true
}