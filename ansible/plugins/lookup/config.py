from ansible.plugins.lookup import LookupBase
import config

class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        return [getattr(config, terms[0])] 