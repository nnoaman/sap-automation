Get-ChildItem Env:* | Select-Object -Property Name,Value

git fetch -q --all
git checkout -q $Env:BUILD_SOURCEBRANCHNAME
git pull
git config --global user.email $Env:BUILDREQUESTEDFOREMAIL
git config --global user.name $Env:BUILDREQUESTEDFOR

$FolderName = "WORKSPACES"
$region = switch ("$Env:DEPLOYER_REGION") {
  "AUCE" { "australiacentral" }
  "AUC2" { "australiacentral2" }
  "AUEA" { "australiaeast" }
  "AUSE" { "australiasoutheast" }
  "BRSO" { "brazilsouth" }
  "BRSE" { "brazilsoutheast" }
  "BRUS" { "brazilus" }
  "CACE" { "canadacentral" }
  "CAEA" { "canadaeast" }
  "CEIN" { "centralindia" }
  "CEUS" { "centralus" }
  "CEUA" { "centraluseuap" }
  "EAAS" { "eastasia" }
  "EAUS" { "eastus" }
  "EUS2" { "eastus2" }
  "FRCE" { "francecentral" }
  "FRSO" { "francesouth" }
  "GENO" { "germanynorth" }
  "GEWC" { "germanywestcentral" }
  "JAEA" { "japaneast" }
  "JAWE" { "japanwest" }
  "JINC" { "jioindiacentral" }
  "JINW" { "jioindiawest" }
  "KOCE" { "koreacentral" }
  "KOSO" { "koreasouth" }
  "NCUS" { "northcentralus" }
  "NOEU" { "northeurope" }
  "NOEA" { "norwayeast" }
  "NOWE" { "norwaywest" }
  "SANO" { "southafricanorth" }
  "SAWE" { "southafricawest" }
  "SCUS" { "southcentralus" }
  "SCUG" { "southcentralusstg" }
  "SOEA" { "southeastasia" }
  "SOIN" { "southindia" }
  "SECE" { "swedencentral" }
  "SWNO" { "switzerlandnorth" }
  "SWWE" { "switzerlandwest" }
  "UACE" { "uaecentral" }
  "UANO" { "uaenorth" }
  "UKSO" { "uksouth" }
  "UKWE" { "ukwest" }
  "WCUS" { "westcentralus" }
  "WEEU" { "westeurope" }
  "WEIN" { "westindia" }
  "WEUS" { "westus" }
  "WUS2" { "westus2" }
}

$msi_id = "$Env:msi_identity_id)".Trim()

$Full = Join-Path -Path $FolderName -ChildPath (Join-Path -Path "DEPLOYER" -ChildPath $Env:DEPLOYER_FOLDER)
$Full_FileName = (Join-Path -path $Full -ChildPath "$Env:DEPLOYER_FILE)")

if (Test-Path $Full) {
  cd $Full

  if (Test-Path $(deployer_file)) {
  }
  else {
    $DeployerFile = New-Item -Path . -Name $(deployer_file) -ItemType "file" -Value ("# Deployer Configuration File" + [Environment]::NewLine)
    Add-Content $(deployer_file) "environment                               = ""$Env:DEPLOYER_ENVIRONMENT"""
    Add-Content $(deployer_file) "location                                  = ""$region"""
    Add-Content $(deployer_file) ""
    Add-Content $(deployer_file) "management_network_logical_name           = ""$Env:DEPLOYER_MANAGEMENT_NETWORK_LOGICAL_NAME"""
    Add-Content $(deployer_file) "management_network_address_space          = ""$Env:ADDRESS_PREFIX.0/24"""
    Add-Content $(deployer_file) "management_subnet_address_prefix          = ""$Env:ADDRESS_PREFIX.64/28"""

    Add-Content $(deployer_file) "$Env:deploy_webapp)"
    Add-Content $(deployer_file) "webapp_subnet_address_prefix              = ""$Env:ADDRESS_PREFIX.192/27"""

    Add-Content $(deployer_file) "$Env:deploy_firewall)"
    Add-Content $(deployer_file) "management_firewall_subnet_address_prefix = ""$Env:ADDRESS_PREFIX.0/26"""

    Add-Content $(deployer_file) "$Env:deploy_bastion)"
    Add-Content $(deployer_file) "management_bastion_subnet_address_prefix = ""$Env:ADDRESS_PREFIX.128/26"""

    Add-Content $(deployer_file) "use_service_endpoint                      = true"
    Add-Content $(deployer_file) "use_private_endpoint                      = true"
    Add-Content $(deployer_file) "enable_rbac_authorization_for_keyvault    = true"
    Add-Content $(deployer_file) "enable_firewall_for_keyvaults_and_storage = true"

    Add-Content $(deployer_file) "deployer_assign_subscription_permissions  = false"

    Add-Content $(deployer_file) "public_network_access_enabled             = false"

    Add-Content $(deployer_file) "$Env:DEPLOYER_COUNT"

    Add-Content $(deployer_file) "$Env:USE_SPN"
    if ($msi_id.Length -gt 0) {
      Add-Content $(deployer_file) "user_assigned_identity_id             = ""$Env_MSI_IS"""
    }
    else {
      Add-Content $(deployer_file) "#user_assigned_identity_id             = ""<user_assigned_identity_id>"""
    }

    git add -f $(deployer_file)
    git commit -m "Added Control Plane configuration[skip ci]"

    git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME
  }

}
else {
  #PowerShell Create directory if not exists
  cd $(Build.Repository.LocalPath)
  $Folder = New-Item $Full -ItemType Directory
  cd $Folder.FullName
  $DeployerFile = New-Item -Path . -Name $(deployer_file) -ItemType "file" -Value ("# Deployer Configuration File" + [Environment]::NewLine)
  Add-Content $(deployer_file) "environment                               = ""$Env:DEPLOYER_ENVIRONMENT"""
  Add-Content $(deployer_file) "location                                  = ""$region"""
  Add-Content $(deployer_file) ""
  Add-Content $(deployer_file) "management_network_logical_name           = ""$Env:deployer_management_network_logical_name)"""
  Add-Content $(deployer_file) "management_network_address_space          = ""$Env:ADDRESS_PREFIX.0/24"""
  Add-Content $(deployer_file) "management_subnet_address_prefix          = ""$Env:ADDRESS_PREFIX.64/28"""

  Add-Content $(deployer_file) "$Env:deploy_webapp)"
  Add-Content $(deployer_file) "webapp_subnet_address_prefix              = ""$Env:ADDRESS_PREFIX.192/27"""

  Add-Content $(deployer_file) "$Env:deploy_firewall)"
  Add-Content $(deployer_file) "management_firewall_subnet_address_prefix = ""$Env:ADDRESS_PREFIX.0/26"""

  Add-Content $(deployer_file) "$Env:deploy_bastion)"
  Add-Content $(deployer_file) "management_bastion_subnet_address_prefix = ""$Env:ADDRESS_PREFIX.128/26"""

  Add-Content $(deployer_file) "use_service_endpoint                      = true"
  Add-Content $(deployer_file) "use_private_endpoint                      = true"
  Add-Content $(deployer_file) "enable_rbac_authorization_for_keyvault    = true"
  Add-Content $(deployer_file) "enable_firewall_for_keyvaults_and_storage = true"


  Add-Content $(deployer_file) "deployer_assign_subscription_permissions  = false"

  Add-Content $(deployer_file) "public_network_access_enabled             = false"

  Add-Content $(deployer_file) "$Env:DEPLOYER_COUNT"
  Add-Content $(deployer_file) ""


  Add-Content $(deployer_file) "$Env:USE_SPN"
  if ($msi_id.Length -gt 0) {
    Add-Content $(deployer_file) "user_assigned_identity_id             = ""$msi_id"""
  }
  else {
    Add-Content $(deployer_file) "#user_assigned_identity_id             = ""<user_assigned_identity_id>"""
  }


  Add-Content $(deployer_file) ""

  Add-Content $(deployer_file) "deployer_image = {"
  Add-Content $(deployer_file) "  os_type         = ""LINUX"","
  Add-Content $(deployer_file) "  type            = ""marketplace"","
  Add-Content $(deployer_file) "  source_image_id = """""
  Add-Content $(deployer_file) "  publisher       = ""Canonical"","
  Add-Content $(deployer_file) "  offer           = ""ubuntu-24_04-lts"","
  Add-Content $(deployer_file) "  sku             = ""server"","
  Add-Content $(deployer_file) "  version         = ""latest"""
  Add-Content $(deployer_file) "}"

  git add -f $(deployer_file)
  git commit -m "Added Control Plane configuration[skip ci]"

  git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME
}

$Full = Join-Path -Path $Env:FOL -ChildPath (Join-Path -Path "LIBRARY" -ChildPath $(library_folder))
$Full_FileName = (Join-Path -path $Full -ChildPath "$Env:LIBRARY_FILE)")
cd $(Build.Repository.LocalPath)

if (Test-Path $Full) {
  cd $Full

  if (Test-Path $(library_file)) {
  }
  else {
    $LibraryFile = New-Item -Path . -Name $(library_file) -ItemType "file" -Value ("# Library Configuration File" + [Environment]::NewLine)
    Add-Content $(library_file) "environment                   = ""$Env:DEPLOYER_ENVIRONMENT"""
    Add-Content $(library_file) "location                      = ""$region"""
    Add-Content $(library_file) ""
    Add-Content $(library_file)
    Add-Content $(library_file) "use_private_endpoint          = true"
    Add-Content $(library_file) "public_network_access_enabled = false"
    Add-Content $(library_file) "$Env:use_spn)"
    Add-Content $(library_file) "dns_label                     = ""$Env:calculated_dns)"""
    git add -f $(library_file)
    git commit -m "Added Control Plane Library configuration[skip ci]"

    git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME
  }

}
else {
  #PowerShell Create directory if not exists
  Write-Host "Creating Library directory"
  cd $(Build.Repository.LocalPath)
  $Folder = New-Item $Full -ItemType Directory
  cd $Full
  Write-Host "Creating Library file"
  $LibraryFile = New-Item -Path . -Name $(library_file) -ItemType "file" -Value ("# Library Configuration File" + [Environment]::NewLine)
  Add-Content $(library_file) "environment                   = ""$Env:DEPLOYER_ENVIRONMENT"""
  Add-Content $(library_file) "location                      = ""$region"""
  Add-Content $(library_file) ""
  Add-Content $(library_file)
  Add-Content $(library_file) "use_private_endpoint          = true"
  Add-Content $(library_file) "public_network_access_enabled = false"
  Add-Content $(library_file) "$Env:use_spn)"
  Add-Content $(library_file) "dns_label                     = ""$Env:calculated_dns)"""
  git add -f $(library_file)
  git commit -m "Added Control Plane Library configuration[skip ci]"

  git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME

}

cd $(Build.Repository.LocalPath)
$FolderName = "pipelines"
$pipeLineName = "01-deploy-control-plane.yml"
$filePath = (Join-Path -path $FolderName -ChildPath $pipeLineName)

                  (Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:control_plane_name)") | Set-Content $filePath
                  (Get-Content $filePath).Replace("MGMT", "$Env:DEPLOYER_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"
git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME

$pipeLineName = "12-remove-control-plane.yml"
$filePath = (Join-Path -path $FolderName -ChildPath $pipeLineName)

                  (Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:control_plane_name)") | Set-Content $filePath
                  (Get-Content $filePath).Replace("MGMT", "$Env:DEPLOYER_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"
git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME

$pipeLineName = "02-sap-workload-zone.yml"
$filePath = (Join-Path -path $FolderName -ChildPath $pipeLineName)

                  (Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:control_plane_name)") | Set-Content $filePath
                  (Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:workload_environment)") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"
git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME

$pipeLineName = "03-sap-system-deployment.yml"
$filePath = (Join-Path -path $FolderName -ChildPath $pipeLineName)

                  (Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:control_plane_name)") | Set-Content $filePath
                  (Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:workload_environment)") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME

$pipeLineName = "04-sap-software-download.yml"
$filePath = (Join-Path -path $FolderName -ChildPath $pipeLineName)

                  (Get-Content $filePath).Replace("WEEU", "$Env:DEPLOYER_REGION") | Set-Content $filePath
                  (Get-Content $filePath).Replace("MGMT", "$Env:DEPLOYER_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME

$pipeLineName = "10-remover-terraform.yml"
$filePath = (Join-Path -path $FolderName -ChildPath $pipeLineName)

                  (Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:control_plane_name)") | Set-Content $filePath
                  (Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:workload_environment)") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

$pipeLineName = "11-remover-arm-fallback.yml"
$filePath = (Join-Path -path $FolderName -ChildPath $pipeLineName)

                  (Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:control_plane_name)") | Set-Content $filePath
                  (Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:workload_environment)") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

$pipeLineName = "12-remove-control-plane.yml"
$filePath = (Join-Path -path $FolderName -ChildPath $pipeLineName)

                  (Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:control_plane_name)") | Set-Content $filePath
                  (Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:workload_environment)") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"
git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME
