
param(
    [string]$SrcSubscriptionName = "Compliance_Tools_Eng",
    [string]$SrcAcrName = "registry1811d0c3",
    [string]$TgtSubscriptionName = "Compliance_Tools_Eng",
    [string]$TargetAcrName = "xiaodongacr"
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
Import-Module (Join-Path $moduleFolder "Common.psm1") -Force
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Sync-ACR"
LoginAzureAsUser -SubscriptionName $SrcSubscriptionName | Out-Null

UsingScope("Retrieving acr pwd") {
    az acr login -n $SrcAcrName | Out-Null
    az acr update -n $SrcAcrName --admin-enabled true | Out-Null
    $SrcAcrCredential = az acr credential show -n $SrcAcrName | ConvertFrom-Json
    $SrcAcrPwd = $SrcAcrCredential.passwords[0].value
    $SrcAcrAuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($SrcAcrName):$($SrcAcrPwd)"))

    az acr login -n $TargetAcrName | Out-Null
    az acr update -n $TargetAcrName --admin-enabled true | Out-Null
    $TgtAcrCredential = az acr credential show -n $TargetAcrName | ConvertFrom-Json
    $TgtAcrPwd = $TgtAcrCredential.passwords[0].value
    $TgtAcrAuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($TargetAcrName):$($TgtAcrPwd)"))
}

UsingScope("Get all images from '$SrcAcrName'") {
    # docker login $LoginServer -u $SpnAppId -p $SrcAcrPwd
    $imageCatalog = Invoke-RestMethod -Headers @{Authorization = ("Basic {0}" -f $SrcAcrAuthHeader) } -Method Get -Uri "https://$SrcAcrName.azurecr.io/v2/_catalog"
    $repositories = $imageCatalog.repositories
    LogInfo -Message "Total of $($repositories.Count) reposities found"
}

UsingScope("Sync docker images from '$SrcAcrName' to '$TargetAcrName'") {
    $totalImagesSynced = 0
    $repositories | ForEach-Object {
        $RepositoryName = $_
        LogStep -Message "Syncing repo $RepositoryName..."

        LogInfo -Message "Getting latest image tag"
        $imageTags = Invoke-RestMethod -Headers @{Authorization = ("Basic {0}" -f $SrcAcrAuthHeader) } -Method Get -Uri "https://$SrcAcrName.azurecr.io/v2/$($RepositoryName)/tags/list"
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
        LogInfo -Message "Picking tag '$tag'"

        LogInfo -Message "Login to '$SrcAcrName'"
        $SrcAcrPwd | docker login "$SrcAcrName.azurecr.io" --username $SrcAcrName --password-stdin | Out-Null

        $SourceImage = "$($SrcAcrName).azurecr.io/$($RepositoryName):$($tag)"
        LogInfo -Message "Pulling image '$SourceImage'..."
        docker pull $SourceImage
        $TargetImage = "$($TargetAcrName).azurecr.io/$($RepositoryName):$($tag)"
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
        LogInfo -Message "Synced $totalImagesSynced of $($repositories.Count) repositories"
    }

    LogInfo -Message "Done!"
}