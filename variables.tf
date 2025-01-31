variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "domain_exists" {
  description = "Set to true if domain already exists in DigitalOcean"
  type        = bool
  default     = true
}

# Removed duplicate manage_domain variable since it's now in main.tf

