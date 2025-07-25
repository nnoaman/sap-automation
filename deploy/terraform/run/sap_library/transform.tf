# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.


locals {
  infrastructure                       = {
                                           environment        = var.environment
                                           region             = var.location
                                           codename           = var.codename
                                           resource_group     = {
                                             name             = var.resourcegroup_name
                                             id               = var.resourcegroup_arm_id
                                             exists           = length(var.resourcegroup_arm_id) > 0
                                               }
                                           tags               = var.tags
                                           assign_permissions = var.assign_permissions
                                           spn_id             = var.spn_id

                                         }
  deployer                             = {
                                           use                       = var.use_deployer
                                         }
  key_vault                            = {
                                           id                        = coalesce(try(data.terraform_remote_state.deployer[0].outputs.deployer_kv_user_arm_id,""), var.spn_keyvault_id, local.spn_key_vault_arm_id)
                                         }
  storage_account_sapbits              = {
                                            id                       = var.library_sapmedia_arm_id
                                            exists                   = length(var.library_sapmedia_arm_id) > 0
                                            name                     = var.library_sapmedia_name
                                            account_tier             = var.library_sapmedia_account_tier
                                            account_replication_type = var.library_sapmedia_account_replication_type
                                            account_kind             = var.library_sapmedia_account_kind
                                            file_share = {
                                              enable_deployment      = var.library_sapmedia_file_share_enable_deployment
                                              is_existing            = var.library_sapmedia_file_share_is_existing
                                              name                   = coalesce(var.library_sapmedia_file_share_name,module.sap_namegenerator.naming.resource_suffixes.sapbits)
                                            }
                                            sapbits_blob_container = {
                                              enable_deployment      = var.library_sapmedia_blob_container_enable_deployment
                                              is_existing            = var.library_sapmedia_blob_container_is_existing
                                              name                   = coalesce(var.library_sapmedia_blob_container_name, module.sap_namegenerator.naming.resource_suffixes.sapbits)
                                            }
                                           shared_access_key_enabled                 = var.shared_access_key_enabled
                                           public_network_access_enabled             = var.public_network_access_enabled
                                           enable_firewall_for_keyvaults_and_storage = var.enable_firewall_for_keyvaults_and_storage
                                         }

   storage_account_tfstate              = {
                                           id                                        = var.library_terraform_state_arm_id
                                           exists                                    = length(var.library_terraform_state_arm_id) > 0
                                           name                                      = var.library_terraform_state_name
                                           account_tier                              = var.library_terraform_state_account_tier
                                           account_replication_type                  = var.library_terraform_state_account_replication_type
                                           account_kind                              = var.library_terraform_state_account_kind
                                           tfstate_blob_container =                  {
                                                                                       is_existing            = var.library_terraform_state_blob_container_is_existing
                                                                                       name                   = var.library_terraform_state_blob_container_name
                                                                                     }

                                           tfvars_blob_container =                   {
                                                                                       is_existing            = var.library_terraform_vars_blob_container_is_existing
                                                                                       name                   = var.library_terraform_vars_blob_container_name
                                                                                     }

                                           ansible_blob_container =                  {
                                                                                       is_existing            = var.library_ansible_blob_container_is_existing
                                                                                       name                   = var.library_ansible_blob_container_name
                                                                                     }

                                           shared_access_key_enabled                 = var.shared_access_key_enabled
                                           public_network_access_enabled             = var.public_network_access_enabled
                                           enable_firewall_for_keyvaults_and_storage = var.enable_firewall_for_keyvaults_and_storage
                                         }

  dns_settings                         = {
                                           use_custom_dns_a_registration             = var.use_custom_dns_a_registration
                                           dns_label                                 = var.dns_label
                                           dns_zone_names                            = var.dns_zone_names

                                           management_dns_resourcegroup_name         = trimspace(var.management_dns_resourcegroup_name)
                                           management_dns_subscription_id            = var.management_dns_subscription_id

                                           privatelink_dns_subscription_id           = var.privatelink_dns_subscription_id != var.management_dns_subscription_id ? var.privatelink_dns_subscription_id : var.management_dns_subscription_id
                                           privatelink_dns_resourcegroup_name        = var.management_dns_resourcegroup_name != var.privatelink_dns_resourcegroup_name ? var.privatelink_dns_resourcegroup_name : var.management_dns_resourcegroup_name

                                           register_storage_accounts_keyvaults_with_dns = var.register_storage_accounts_keyvaults_with_dns
                                           register_endpoints_with_dns               = var.register_endpoints_with_dns

                                           create_privatelink_dns_zones              = var.create_privatelink_dns_zones

                                           additional_network_id                     = trimspace(coalesce(var.additional_network_id,
                                                                                                          var.use_deployer ? contains(keys(data.terraform_remote_state.deployer[0].outputs), "additional_network_id") ? data.terraform_remote_state.deployer[0].outputs.additional_network_id : "" : "",
                                                                                                          " "))

                                         }
}
