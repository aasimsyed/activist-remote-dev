variable "ssh_key_name" {
  description = "Name of the SSH key in DigitalOcean"
  type        = string
}

variable "size" {
  description = "Droplet size"
  type        = string
}

variable "region" {
  description = "Droplet region"
  type        = string
}

variable "image" {
  description = "Droplet image"
  type        = string
}

variable "vpc_uuid" {
  description = "VPC UUID"
  type        = string
}

variable "backups" {
  description = "Enable backups"
  type        = bool
  default     = false
}

variable "monitoring" {
  description = "Enable monitoring"
  type        = bool
  default     = true
}

variable "branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
} 