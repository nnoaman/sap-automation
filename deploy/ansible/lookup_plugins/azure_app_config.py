# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

from __future__ import absolute_import, division, print_function

__metaclass__ = type

DOCUMENTATION = """
    lookup: azure_app_config
    author:
        - Hai Cao <cao.hai@microsoft.com>
        - SDAF Core Dev Team <sdaf_core_team@microsoft.com>
    version_added: 2.16
    requirements:
        - requests
        - azure-identity
        - azure-appconfiguration
    short_description: Read configuration value from Azure App Configuration.
    description:
      - This lookup returns the content of a configuration value saved in Azure App Configuration.
      - When ansible host is MSI enabled Azure VM, user don't need provide any credential to access to Azure App Configuration.
    options:
        _terms:
            description: Configuration key.
            required: True
        config_label:
            description: Label for the configuration setting.
            required: False
        appconfig_url:
            description: URL of Azure App Configuration.
            required: True
        client_id:
            description: Client id of service principal that has access to the Azure App Configuration.
            required: False
        client_secret:
            description: Secret of the service principal.
            required: False
        tenant_id:
            description: Tenant id of service principal.
            required: False
        timeout:
            description: Timeout (in seconds) for checking endpoint responsiveness. Default is 5.
            required: False
    notes:
        - If Ansible is running on an Azure Virtual Machine with MSI enabled, client_id, client_secret and tenant_id aren't required.
        - |
            For enabling MSI on Azure VM, please refer to:
            https://docs.microsoft.com/en-us/azure/active-directory/managed-service-identity/
        - After enabling MSI on Azure VM, remember to grant access of the App Configuration to the VM by adding a new Access Policy in Azure Portal.
        - If MSI is not enabled on Ansible host, it's required to provide a valid service principal which has access to the App Configuration.
"""

EXAMPLES = """
- name: Look up configuration value when Ansible host is MSI enabled Azure VM
  debug: msg="The configuration value is {{lookup('azure_appconfig', 'testConfig', appconfig_url='https://yourappconfig.azconfig.io')}}"

- name: Look up configuration value when Ansible host is general VM
  vars:
    url: 'https://yourappconfig.azconfig.io'
    config_key: 'testConfig'
    client_id: '123456789'
    client_secret: 'abcdefg'
    tenant_id: 'uvwxyz'
    timeout: 10
  debug: msg="The configuration value is {{lookup('azure_appconfig', config_key, appconfig_url=url, client_id=client_id, client_secret=client_secret, tenant_id=tenant_id, timeout=timeout)}}"
"""

RETURN = """
  _raw:
    description: configuration value string
"""

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
from ansible.utils.display import Display
from azure.identity import (
    DefaultAzureCredential,
    ClientSecretCredential,
    ManagedIdentityCredential,
)
from azure.appconfiguration import AzureAppConfigurationClient
import requests

display = Display()


class AzureAppConfigHelper:
    """
    A helper class for retrieving configuration settings from Azure App Configuration.
    It handles URL responsiveness (public vs. private endpoints), credential selection,
    and configuration retrieval.
    """

    def __init__(
        self,
        appconfig_url,
        client_id=None,
        client_secret=None,
        tenant_id=None,
        timeout=5,
    ):
        """
        Initialize the helper with the provided App Configuration URL and credentials.
        :param appconfig_url: The base URL for Azure App Configuration.
        :param client_id: Optional client (or managed identity) ID.
        :param client_secret: Optional client secret.
        :param tenant_id: Optional tenant id.
        :param timeout: Timeout (in seconds) for responsiveness check.
        """
        # Cache the responsive URL for reuse.
        self.appconfig_url = self.get_responsive_url(appconfig_url, timeout)
        self.credential = self.get_credential(client_id, client_secret, tenant_id)
        self.client = AzureAppConfigurationClient(
            appconfig_url=self.appconfig_url, credential=self.credential
        )
        display.v(
            f"Initialized AzureAppConfigHelper with appconfig_url: {self.appconfig_url}"
        )

    def get_responsive_url(self, appconfig_url, timeout=5):
        """
        Tests both public and private endpoints and returns the first responsive URL.
        :param appconfig_url: The base URL for Azure App Configuration.
        :param timeout: Timeout in seconds for endpoint responsiveness.
        :return: A responsive URL string.
        """
        public_url = appconfig_url
        private_url = appconfig_url.replace(".azconfig.io", ".private.azconfig.io")

        for url in [private_url, public_url]:
            try:
                response = requests.get(url, timeout=timeout)
                if response.status_code == 200:
                    display.v(f"Using responsive URL: {url}")
                    return url
            except requests.RequestException:
                display.v(f"URL not responsive: {url}")

        raise AnsibleError(
            "Failed to connect to both public and private endpoints of Azure App Configuration."
        )

    def get_credential(self, client_id, client_secret, tenant_id):
        """
        Returns the appropriate credential based on provided parameters.
        :return: An Azure credential object.
        """
        if client_id and client_secret and tenant_id:
            display.v("Using ClientSecretCredential for authentication")
            return ClientSecretCredential(
                client_id=client_id, client_secret=client_secret, tenant_id=tenant_id
            )
        elif client_id:
            display.v("Using ManagedIdentityCredential for authentication")
            return ManagedIdentityCredential(client_id=client_id)
        else:
            display.v("Using DefaultAzureCredential for authentication")
            return DefaultAzureCredential()

    def get_configuration(self, config_key, config_label=None):
        """
        Retrieves the configuration setting from Azure App Configuration.
        :param config_key: The configuration key.
        :param config_label: The label (optional) for the configuration.
        :return: The value of the configuration setting.
        """
        try:
            display.v(
                f"Fetching configuration: {config_key} with label: {config_label}"
            )
            config = self.client.get_configuration_setting(
                key=config_key, label=config_label
            )
            display.v(
                f"Successfully fetched configuration: {config_key} with label: {config_label}"
            )
            return config.value
        except Exception as e:
            display.error(
                f"Failed to fetch configuration {config_key} with label {config_label}: {str(e)}"
            )
            raise AnsibleError(
                f"Failed to fetch configuration {config_key} with label {config_label}: {str(e)}"
            )


class LookupModule(LookupBase):
    """
    Ansible lookup module for retrieving configuration settings from Azure App Configuration.
    """

    def run(self, terms, variables, **kwargs):
        appconfig_url = kwargs.get("appconfig_url")
        client_id = kwargs.get("client_id")
        client_secret = kwargs.get("client_secret")
        tenant_id = kwargs.get("tenant_id")
        config_label = kwargs.get("config_label")
        timeout = kwargs.get(
            "timeout", 5
        )  # Allow the user to customize the URL check timeout

        if not appconfig_url:
            display.error("Failed to get a valid appconfig URL.")
            raise AnsibleError("Failed to get a valid appconfig URL.")

        # Initialize the helper with the provided timeout value.
        helper = AzureAppConfigHelper(
            appconfig_url, client_id, client_secret, tenant_id, timeout
        )
        ret = []

        for term in terms:
            try:
                config_value = helper.get_configuration(term, config_label)
                ret.append(config_value)
            except AnsibleError as e:
                display.error(str(e))
                raise

        return ret
