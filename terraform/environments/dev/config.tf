locals {
  # Read base config from provided path
  config = yamldecode(file(var.config_path))
  
  # Extract commonly used configurations
  deploy = local.config.deploy
  security = local.config.security
}