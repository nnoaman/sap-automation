# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

from __future__ import absolute_import, division, print_function

__metaclass__ = type

DOCUMENTATION = """
    lookup: azure_keyvault_secret
    author:
        - Hai Cao <cao.hai@microsoft.com>
        - SDAF Core Dev Team <sdaf_core_team@microsoft.com>
    version_added: 2.7
    requirements:
        - requests
        - azure-identity
        - azure-keyvault-secrets
    short_description: Read secret from Azure Key Vault.
    description:
      - This lookup returns the content of a secret saved in Azure Key Vault.
      - When an Ansible host is MSI-enabled on an Azure VM, credentials are not required.
    options:
        _terms:
            description: Secret name. Optionally, the secret version can be included like secret_name/secret_version.
            required: True
        vault_url:
            description: URL of Azure Key Vault.
            required: True
        client_id:
            description: Client ID of the service principal that has access to the Key Vault.
        client_secret:
            description: Secret of the service principal.
        tenant_id:
            description: Tenant ID of the service principal.
        timeout:
            description: Timeout (in seconds) for endpoint responsiveness check. Default is 5.
    notes:
        - If version is not provided, this plugin returns the latest version of the secret.
        - When Ansible is running on an Azure Virtual Machine with MSI enabled, client_id, client_secret and tenant_id aren't required.
        - For enabling MSI on Azure VM, see https://docs.microsoft.com/en-us/azure/active-directory/managed-service-identity/
        - After enabling MSI, ensure the Key Vault access policy includes the VM.
        - If MSI is not enabled, a valid service principal must be provided.
"""

EXAMPLES = """
- name: Look up secret on MSI-enabled Azure VM
  debug: msg="The secret value is {{lookup('azure_keyvault_secret','testSecret/version', vault_url='https://yourvault.vault.azure.net')}}"

- name: Look up secret on a general VM
  vars:
    url: 'https://yourvault.vault.azure.net'
    secretname: 'testSecret/version'
    client_id: '123456789'
    client_secret: 'abcdefg'
    tenant_id: 'uvwxyz'
  debug: msg="The secret value is {{lookup('azure_keyvault_secret', secretname, vault_url=url, client_id=client_id, client_secret=client_secret, tenant_id=tenant_id)}}"
"""

RETURN = """
  _raw:
    description: secret content string
"""

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
from ansible.utils.display import Display
from azure.identity import (
    DefaultAzureCredential,
    ClientSecretCredential,
    ManagedIdentityCredential,
)
from azure.keyvault.secrets import SecretClient
import requests

display = Display()


class AzureKeyVaultHelper:
    """
    A helper class for retrieving secrets from Azure Key Vault.
    It handles endpoint responsiveness (public vs. private endpoints),
    credential selection, and secret retrieval.
    """

    def __init__(
        self, vault_url, client_id=None, client_secret=None, tenant_id=None, timeout=5
    ):
        """
        Initialize the helper with the provided Key Vault URL and credentials.
        :param vault_url: The base URL for Azure Key Vault.
        :param client_id: Optional client (or managed identity) ID.
        :param client_secret: Optional client secret.
        :param tenant_id: Optional tenant ID.
        :param timeout: Timeout (in seconds) for checking endpoint responsiveness.
        """
        # Determine and cache the responsive URL.
        self.vault_url = self.get_responsive_url(vault_url, timeout)
        self.credential = self.get_credential(client_id, client_secret, tenant_id)
        self.client = SecretClient(vault_url=self.vault_url, credential=self.credential)
        display.v(f"Initialized AzureKeyVaultHelper with vault_url: {self.vault_url}")

    def get_responsive_url(self, vault_url, timeout=5):
        """
        Tests both public and private endpoints and returns the first responsive URL.
        For the private endpoint, we assume the URL uses the "privatelink" domain.
        :param vault_url: Base URL for Azure Key Vault.
        :param timeout: Timeout (in seconds) for endpoint responsiveness.
        :return: A responsive URL string.
        """
        # Assume public URL is provided (e.g., https://yourvault.vault.azure.net)
        public_url = vault_url
        # Derive private endpoint URL (e.g., https://yourvault.privatelink.vault.azure.net)
        private_url = vault_url.replace(
            ".vault.azure.net", ".privatelink.vault.azure.net"
        )

        for url in [private_url, public_url]:
            try:
                response = requests.get(url, timeout=timeout)
                if response.status_code == 200:
                    display.v(f"Using responsive URL: {url}")
                    return url
            except requests.RequestException:
                display.v(f"URL not responsive: {url}")

        raise AnsibleError(
            "Failed to connect to both public and private endpoints of Azure Key Vault."
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

    def get_secret(self, secret_name):
        """
        Retrieves the secret from Azure Key Vault.
        :param secret_name: The secret name (optionally with version, e.g., secret_name/version).
        :return: The secret value.
        """
        try:
            display.v(f"Fetching secret: {secret_name}")
            secret = self.client.get_secret(secret_name)
            display.v(f"Successfully fetched secret: {secret_name}")
            return secret.value
        except Exception as e:
            display.error(f"Failed to fetch secret {secret_name}: {str(e)}")
            raise AnsibleError(f"Failed to fetch secret {secret_name}: {str(e)}")


class LookupModule(LookupBase):
    """
    Ansible lookup module for retrieving secrets from Azure Key Vault.
    """

    def run(self, terms, variables, **kwargs):
        vault_url = kwargs.get("vault_url")
        client_id = kwargs.get("client_id")
        client_secret = kwargs.get("client_secret")
        tenant_id = kwargs.get("tenant_id")
        timeout = kwargs.get("timeout", 5)  # Allow configuring a custom timeout

        if not vault_url:
            display.error("Failed to get a valid vault url.")
            raise AnsibleError("Failed to get a valid vault url.")

        # Initialize the helper with the provided timeout value.
        helper = AzureKeyVaultHelper(
            vault_url, client_id, client_secret, tenant_id, timeout
        )
        ret = []

        for term in terms:
            try:
                secret_value = helper.get_secret(term)
                ret.append(secret_value)
            except AnsibleError as e:
                display.error(str(e))
                raise

        return ret
