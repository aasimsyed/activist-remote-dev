"""
Ansible lookup plugin for retrieving values from config module.

This plugin allows playbooks to access configuration values stored in a Python module,
enabling dynamic configuration lookups during playbook execution.
"""
from ansible.plugins.lookup import LookupBase
from ansible.config.manager import ConfigManager



class LookupModule(LookupBase):
    """
    Lookup plugin for retrieving configuration values from Ansible config manager.
    Returns the value of the requested configuration parameter.
    """
    def run(self, terms, variables=None, **kwargs):
        config = ConfigManager()
        return [config.get_config_value(terms[0])]
