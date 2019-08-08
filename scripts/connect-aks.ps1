
param(
    [string] $SettingName = "aamva"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}
$infraFolder = Join-Path $gitRootFolder "infra"
$settingsFolder = Join-Path $infraFolder "settings"
$tempFolder = Join-Path $scriptFolder "temp"
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}
$tempFolder = Join-Path $tempFolder $SettingName
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}

$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Connect-AKS"


UsingScope("retrieving settings") {
    $settingYamlFile = Join-Path $settingsFolder "$($SettingName).yaml"
    $settings = Get-Content $settingYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Settings retrieved for '$($settings.global.subscriptionName)'"
}


UsingScope("login") {
    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount -or $azAccount.name -ne $settings.global.subscriptionName) {
        az login
        az account set -s $settings.global.subscriptionName
        $azAccount = az account show | ConvertFrom-Json
    }

    $settings.global["subscriptionId"] = $azAccount.id
    $settings.global["tenantId"] = $azAccount.tenantId
}


UsingScope("Connect to aks") {
    az aks get-credentials --resource-group $settings.global.resourceGroup.name --name $settings.aks.clusterName --overwrite-existing --admin
    $currentContextName = kubectl config current-context
    LogInfo -Message "You are now connected to k8s. '$currentContextName'"
}


UsingScope("Open dashboard") {
    $Port = 8082
    $isWindowsOs = ($PSVersionTable.PSVersion.Major -lt 6) -or ($PSVersionTable.Platform -eq "Win32NT")
    $isUnix = $PSVersionTable.Contains("Platform") -and ($PSVersionTable.Platform -eq "Unix")
    $isMac = $PSVersionTable.Contains("Platform") -and ($PSVersionTable.OS.Contains("Darwin"))
    $dashboardUrl = "http://localhost:$($Port)/api/v1/namespaces/kube-system/services/http:kubernetes-dashboard:/proxy/#!/overview?namespace=default"
    if ($isMac -or $isUnix) {
        Invoke-Expression "kubectl proxy --port=$Port &"
        & open $dashboardUrl
    }
    else {
        Start-Process powershell "kubectl proxy --port=$Port"
        Start-Process $dashboardUrl
    }
}