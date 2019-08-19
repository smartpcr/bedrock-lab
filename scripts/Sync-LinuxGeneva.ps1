
param(
    [string]$AcrName = "linuxgeneva-microsoft",
    [string]$VaultName = "xiaodong-kv",
    [string]$SpnAppId = "c33eca9e-d787-4955-b9ff-b61b2b2ebc73",
    [string]$SpnPwdSecretName = "sace-acr-spn-pwd",
    [string]$TargetAcrName = "xiaodongacr",
    [string]$TargetAcrPwdSecretName = "xiaodongacr-pwd"
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
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Common.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Sync-LinuxGeneva-ACR"
LoginAzureAsUser -SubscriptionName $SrcSubscriptionName | Out-Null

UsingScope("Retrieving acr pwd") {
    $SpnPwdSecret = az keyvault secret show --vault-name $VaultName --name $SpnPwdSecretName | ConvertFrom-Json
    $SrcAcrPwd = $SpnPwdSecret.value
    $SrcAcrAuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($SpnAppId):$($SrcAcrPwd)"))

    $TgtAcrPwdSecret = az keyvault secret show --vault-name $VaultName --name $TargetAcrPwdSecretName | ConvertFrom-Json
    $TgtAcrPwd = $TgtAcrPwdSecret.value
    $TgtAcrAuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($TargetAcrName):$($TgtAcrPwd)"))
}

UsingScope("Get all images from '$AcrName'") {
    # docker login $LoginServer -u $SpnAppId -p $SrcAcrPwd
    $imageCatalog = Invoke-RestMethod -Headers @{Authorization = ("Basic {0}" -f $SrcAcrAuthHeader) } -Method Get -Uri "https://$AcrName.azurecr.io/v2/_catalog"
    $repositories = $imageCatalog.repositories
    LogInfo -Message "Total of $($repositories.Count) reposities found"
}

UsingScope("Sync docker images from '$AcrName' to '$TargetAcrName'") {
    $totalImagesSynced = 0
    $repositories | ForEach-Object {
        $RepositoryName = $_
        LogStep -Message "Syncing repo $RepositoryName..."

        LogInfo -Message "Getting latest image tag"
        $imageTags = Invoke-RestMethod -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) } -Method Get -Uri "https://$AcrName.azurecr.io/v2/$($RepositoryName)/tags/list"
        $tag = ""
        [Int64] $lastTag = 0
        $imageTags.tags | ForEach-Object {
            if ($_ -eq "latest" -and $tag -ne $_) {
                $tag = $_
            }
            elseif ($_ -ne "latest" -and $tag -ne "latest") {
                $currentTag = $_
                if ($currentTag -match "(\d+)$") {
                    $tagNum = [Int64] $Matches[1]
                    if ($tagNum -gt $lastTag) {
                        $lastTag = $tagNum
                        $tag = $currentTag
                    }
                }
            }
        }
        if ($tag -eq "") {
            throw "Failed to get image tag"
        }
        LogInfo -Message "Picking tag '$lastTag'"

        LogInfo -Message "Login to '$AcrName'"
        $SrcAcrPwd | docker login "$AcrName.azurecr.io" --username $SpnAppId --password-stdin | Out-Null

        $SourceImage = "$($AcrName).azurecr.io/$($RepositoryName):$($lastTag)"
        LogInfo -Message "Pulling image '$SourceImage'..."
        docker pull $SourceImage
        $TargetImage = "$($TargetAcrName).azurecr.io/$($RepositoryName):$($lastTag)"
        docker tag $SourceImage $TargetImage

        LogInfo -Message "Login to '$TargetAcrName'"
        $TgtAcrPwd | docker login "$TargetAcrName.azurecr.io" --username $TargetAcrName --password-stdin | Out-Null

        LogInfo -Message "Pushing image '$SourceImage'..."
        docker push $TargetImage

        LogInfo -Message "Clearing image '$RepositoryName' from disk"
        $targetImageId = $(docker images -q --filter "reference=$TargetImage")
        if ($targetImageId) {
            docker image rm $targetImageId -f
        }
        $sourceImageId = $(docker images -q --filter "reference=$SourceImage")
        if ($sourceImageId) {
            docker image rm $sourceImageId -f
        }

        $totalImagesSynced++
        LogInfo -Message "Syncing $totalImagesSynced of $($repositories.Count) repositories"
    }

    LogInfo -Message "Done!"
}