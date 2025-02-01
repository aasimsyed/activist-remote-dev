variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "config_path" {
  description = "Path to the configuration file"
  type        = string
}

variable "delete_all" {
  description = "Whether to allow destruction of all resources"
  type        = bool
  default     = false
} 