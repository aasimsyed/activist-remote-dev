"""Configuration management module for loading and accessing application settings.

Provides a singleton Config class that handles YAML configuration files with support
for multiple configuration paths and dot notation access to nested values."""

from pathlib import Path
import yaml

class Config:
    """Singleton configuration manager that loads and provides access to application settings.
    
    Loads configuration from YAML files in multiple possible locations with fallback support.
    Access values using dot notation via the get() method."""

    _instance = None
    _config = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(Config, cls).__new__(cls)
        return cls._instance

    def __init__(self):
        if self._config is None:
            self.load_config()

    def load_config(self):
        """Load configuration from YAML files in predefined locations.
        
        Searches for config.yml in project, user, and system directories.
        Raises FileNotFoundError if no configuration file is found."""

        config_paths = [
            Path("config.yml"),
            Path("~/.config/activist/config.yml").expanduser(),
            Path("/etc/activist/config.yml"),
        ]

        for path in config_paths:
            if path.exists():
                with open(path, 'r', encoding='utf-8') as f:
                    self._config = yaml.safe_load(f)
                return

        raise FileNotFoundError("No configuration file found")

    def get(self, path, default=None):
        """Get configuration value using dot notation"""
        keys = path.split('.')
        value = self._config
        for key in keys:
            if not isinstance(value, dict):
                return default
            value = value.get(key, default)
            if value is None:
                return default
        return value
