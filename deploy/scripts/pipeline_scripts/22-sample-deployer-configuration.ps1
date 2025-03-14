Get-ChildItem Env:* | Select-Object -Property Name, Value | Sort-Object Name
$RootFolder = Join-Path -Path $Env:CONFIG_REPO_PATH -ChildPath "WORKSPACES"
Set-Location $RootFolder

Write-Host Get-Location
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

$msi_id = "$Env:MSI_IDENTITY_ID".Trim()

$Full = Join-Path -Path $RootFolder -ChildPath (Join-Path -Path "DEPLOYER" -ChildPath $Env:DEPLOYER_FOLDER)
$Full_FileName = (Join-Path -path $Full -ChildPath "$Env:DEPLOYER_FILE")

if (Test-Path $Full) {
  Set-Location $Full
}
else {
  #PowerShell Create directory if not exists

  Set-Location (Join-Path -Path $RootFolder -ChildPath "DEPLOYER")
  $Folder = New-Item $Env:DEPLOYER_FOLDER -ItemType Directory
  Set-Location $Env:DEPLOYER_FOLDER

}


if ( -not (Test-Path -Path $Env:DEPLOYER_FILE)  ) {
  $DeployerFile = New-Item -Path . -Name $Env:DEPLOYER_FILE -ItemType "file" -Value ("# Deployer Configuration File" + [Environment]::NewLine)
  Add-Content $DeployerFile "environment                               = ""$Env:DEPLOYER_ENVIRONMENT"""
  Add-Content $DeployerFile "location                                  = ""$region"""
  Add-Content $DeployerFile ""
  Add-Content $DeployerFile "management_network_logical_name           = ""$Env:DEPLOYER_MANAGEMENT_NETWORK_LOGICAL_NAME"""
  Add-Content $DeployerFile "management_network_address_space          = ""$Env:ADDRESS_PREFIX.0/24"""
  Add-Content $DeployerFile "management_subnet_address_prefix          = ""$Env:ADDRESS_PREFIX.64/28"""

  Add-Content $DeployerFile "$Env:deploy_webapp)"
  Add-Content $DeployerFile "webapp_subnet_address_prefix              = ""$Env:ADDRESS_PREFIX.192/27"""

  Add-Content $DeployerFile "$Env:DEPLOY_FIREWALL"
  Add-Content $DeployerFile "management_firewall_subnet_address_prefix = ""$Env:ADDRESS_PREFIX.0/26"""

  Add-Content $DeployerFile "$Env:DEPLOY_BASTION"
  Add-Content $DeployerFile "management_bastion_subnet_address_prefix = ""$Env:ADDRESS_PREFIX.128/26"""

  Add-Content $DeployerFile "use_service_endpoint                      = true"
  Add-Content $DeployerFile "use_private_endpoint                      = true"
  Add-Content $DeployerFile "enable_rbac_authorization_for_keyvault    = true"
  Add-Content $DeployerFile "enable_firewall_for_keyvaults_and_storage = true"

  Add-Content $DeployerFile "deployer_assign_subscription_permissions  = false"

  Add-Content $DeployerFile "public_network_access_enabled             = false"

  Add-Content $DeployerFile "$Env:DEPLOYER_COUNT"

  Add-Content $DeployerFile "$Env:USE_SPN"
  if ($msi_id.Length -gt 0) {
    Add-Content $DeployerFile "user_assigned_identity_id             = ""$msi_id"""
  }
  else {
    Add-Content $DeployerFile "#user_assigned_identity_id             = ""<user_assigned_identity_id>"""
  }
  Add-Content $Env:DEPLOYER_FILE ""

  Add-Content $Env:DEPLOYER_FILE "deployer_image = {"
  Add-Content $Env:DEPLOYER_FILE "  os_type         = ""LINUX"","
  Add-Content $Env:DEPLOYER_FILE "  type            = ""marketplace"","
  Add-Content $Env:DEPLOYER_FILE "  source_image_id = """""
  Add-Content $Env:DEPLOYER_FILE "  publisher       = ""Canonical"","
  Add-Content $Env:DEPLOYER_FILE "  offer           = ""ubuntu-24_04-lts"","
  Add-Content $Env:DEPLOYER_FILE "  sku             = ""server"","
  Add-Content $Env:DEPLOYER_FILE "  version         = ""latest"""
  Add-Content $Env:DEPLOYER_FILE "}"


  git add -f $DeployerFile
  git commit -m "Added Control Plane configuration[skip ci]"

  git -c http.extraheader="AUTHORIZATION: bearer $Env:SYSTEM_ACCESSTOKEN" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME
}

$Full = Join-Path -Path $RootFolder -ChildPath (Join-Path -Path "LIBRARY" -ChildPath $Env:LIBRARY_FOLDER)
$Full_FileName = (Join-Path -path $Full -ChildPath "$Env:LIBRARY_FILE")

if (Test-Path $Full) {
  Set-Location $Full
}
else {
  #PowerShell Create directory if not exists

  Set-Location (Join-Path -Path $RootFolder -ChildPath "LIBRARY")
  $Folder = New-Item $Env:LIBRARY_FOLDER -ItemType Directory
  Set-Location $Env:LIBRARY_FOLDER
}

if ( -not (Test-Path -Path $Env:LIBRARY_FILE)  ) {
  $LibraryFile = New-Item -Path . -Name $Env:LIBRARY_FILE -ItemType "file" -Value ("# Library Configuration File" + [Environment]::NewLine)
  Add-Content $Env:LIBRARY_FILE "environment                   = ""$Env:DEPLOYER_ENVIRONMENT"""
  Add-Content $Env:LIBRARY_FILE "location                      = ""$region"""
  Add-Content $Env:LIBRARY_FILE ""
  Add-Content $Env:LIBRARY_FILE
  Add-Content $Env:LIBRARY_FILE "use_private_endpoint          = true"
  Add-Content $Env:LIBRARY_FILE "public_network_access_enabled = false"
  Add-Content $Env:LIBRARY_FILE "$Env:use_spn)"
  Add-Content $Env:LIBRARY_FILE "dns_label                     = ""$Env:CALCULATED_DNS)"""
  git add -f $Env:LIBRARY_FILE
  git commit -m "Added Control Plane Library configuration[skip ci]"

  git -c http.extraheader="AUTHORIZATION: bearer $Env:SYSTEM_ACCESSTOKEN" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME
}


Set-Location $Env:CONFIG_REPO_PATH
$FolderName = "pipelines"
$pipeLineName = "01-deploy-control-plane.yml"
$filePath = Join-Path -path $Env:CONFIG_REPO_PATH - -ChildPath (Join-Path -path $FolderName -ChildPath $pipeLineName)
(Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:CONTROL_PLANE_NAME") | Set-Content $filePath
(Get-Content $filePath).Replace("MGMT", "$Env:DEPLOYER_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

$pipeLineName = "12-remove-control-plane.yml"
$filePath = Join-Path -path $Env:CONFIG_REPO_PATH - -ChildPath (Join-Path -path $FolderName -ChildPath $pipeLineName)

(Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:CONTROL_PLANE_NAME") | Set-Content $filePath
(Get-Content $filePath).Replace("MGMT", "$Env:DEPLOYER_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

$pipeLineName = "02-sap-workload-zone.yml"
$filePath = Join-Path -path $Env:CONFIG_REPO_PATH - -ChildPath (Join-Path -path $FolderName -ChildPath $pipeLineName)

(Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:CONTROL_PLANE_NAME") | Set-Content $filePath
(Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:WORKLOAD_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

$pipeLineName = "03-sap-system-deployment.yml"
$filePath = Join-Path -path $Env:CONFIG_REPO_PATH - -ChildPath (Join-Path -path $FolderName -ChildPath $pipeLineName)

(Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:CONTROL_PLANE_NAME") | Set-Content $filePath
(Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:WORKLOAD_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"


$pipeLineName = "04-sap-software-download.yml"
$filePath = Join-Path -path $Env:CONFIG_REPO_PATH - -ChildPath (Join-Path -path $FolderName -ChildPath $pipeLineName)

(Get-Content $filePath).Replace("WEEU", "$Env:DEPLOYER_REGION") | Set-Content $filePath
(Get-Content $filePath).Replace("MGMT", "$Env:DEPLOYER_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"


$pipeLineName = "10-remover-terraform.yml"
$filePath = Join-Path -path $Env:CONFIG_REPO_PATH - -ChildPath (Join-Path -path $FolderName -ChildPath $pipeLineName)

(Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:CONTROL_PLANE_NAME") | Set-Content $filePath
(Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:WORKLOAD_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

$pipeLineName = "11-remover-arm-fallback.yml"
$filePath = Join-Path -path $Env:CONFIG_REPO_PATH - -ChildPath (Join-Path -path $FolderName -ChildPath $pipeLineName)

(Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:CONTROL_PLANE_NAME") | Set-Content $filePath
(Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:WORKLOAD_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"

$pipeLineName = "12-remove-control-plane.yml"
$filePath = Join-Path -path $Env:CONFIG_REPO_PATH - -ChildPath (Join-Path -path $FolderName -ChildPath $pipeLineName)

(Get-Content $filePath).Replace("MGMT-WEEU-DEP01", "$Env:CONTROL_PLANE_NAME") | Set-Content $filePath
(Get-Content $filePath).Replace("DEV-WEEU-SAP01", "$Env:WORKLOAD_ENVIRONMENT") | Set-Content $filePath

git add -f $filePath
git commit -m "Update $pipeLineName[skip ci]"
git -c http.extraheader="AUTHORIZATION: bearer $Env:SYSTEM_ACCESSTOKEN" push --set-upstream origin $Env:BUILD_SOURCEBRANCHNAME
