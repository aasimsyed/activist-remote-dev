variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "app_name" {
  description = "Application name used for resource naming"
  type        = string
  default     = "activist"
} 