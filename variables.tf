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

variable "manage_domain" {
  type    = bool
  default = false  # Default to using existing domain
  description = "Set to true to create/manage domain, false to use existing"
}

