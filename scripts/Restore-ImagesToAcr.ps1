
param(
    [string]$SettingName = "sace"
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
$imagesFolder = Join-Path $settingsFolder "images"
$infraImagesYamlFile = Join-Path $imagesFolder "infra.yaml"
$svcImagesYamlFile = Join-Path $imagesFolder "svc.yaml"

$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "Logging.psm1") -Force
Import-Module (Join-Path $moduleFolder "Common.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "AcrUtil.psm1") -Force
$tempFolder = Join-Path $scriptFolder "temp"
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}
$tempFolder = Join-Path $tempFolder $SettingName
if (-not (Test-Path $tempFolder)) {
    New-Item $tempFolder -ItemType Directory -Force | Out-Null
}

InitializeLogger -ScriptFolder $scriptFolder -ScriptName "Restore-ACR"

UsingScope("retrieving settings") {
    $settingYamlFile = Join-Path $settingsFolder "$($SettingName).yaml"
    $settings = Get-Content $settingYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Settings retrieved for '$($settings.global.subscriptionName)'"

    $infraImages = Get-Content $infraImagesYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Total of $($infraImages.images.Count) images found for infra"

    $svcImages = Get-Content $svcImagesYamlFile -Raw | ConvertFrom-Yaml
    LogStep -Message "Total of $($svcImages.images.Count) images found for svc"
}

UsingScope("login") {
    $azAccount = LoginAzureAsUser -SubscriptionName $settings.global.subscriptionName
    $settings.global["subscriptionId"] = $azAccount.id
    $settings.global["tenantId"] = $azAccount.tenantId
    LogStep -Message "Logged in as user '$($azAccount.name)'"
}

UsingScope("Retrieving acr pwd") {
    if ($infraImages.backup.subscription -ne $settings.global.subscriptionName) {
        LoginAzureAsUser -SubscriptionName $infraImages.backup.subscription | Out-Null
    }
    $SrcAcrName = $infraImages.backup.acrName
    az acr login -n $SrcAcrName | Out-Null
    az acr update -n $SrcAcrName --admin-enabled true | Out-Null
    $SrcAcrCredential = az acr credential show -n $SrcAcrName | ConvertFrom-Json
    $SrcAcrPwd = $SrcAcrCredential.passwords[0].value
    $SrcAcrAuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($SrcAcrName):$($SrcAcrPwd)"))

    if ($infraImages.backup.subscription -ne $settings.global.subscriptionName) {
        LoginAzureAsUser -SubscriptionName $settings.global.subscriptionName | Out-Null
    }
    $TgtAcrName = $settings.acr.name
    az acr login -n $TgtAcrName | Out-Null
    az acr update -n $TgtAcrName --admin-enabled true | Out-Null
    $TgtAcrCredential = az acr credential show -n $TgtAcrName | ConvertFrom-Json
    $TgtAcrPwd = $TgtAcrCredential.passwords[0].value
    $TgtAcrAuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($TgtAcrName):$($TgtAcrPwd)"))
}

UsingScope("Retrieving images from target acr") {
    $imagesInTargetAcr = GetImagesWithTags -SubscriptionName $settings.global.subscriptionName -AcrName $settings.acr.name
    if ($null -eq $imagesInTargetAcr) {
        $imagesInTargetAcr = New-Object System.Collections.ArrayList
    }
    LogInfo -Message "Total of $($imagesInTargetAcr.Count) images found"
}

UsingScope("Restoring infra images") {
    $totalImagesSynced = 0

    $infraImages.images | ForEach-Object {
        $imageName = $_.name
        $imageTag = $_.tag
        [array] $foundInTgtAcr = $imagesInTargetAcr | Where-Object { $_.name -eq $imageName -and $_.tag -eq $imageTag }
        if ($null -ne $foundInTgtAcr -and $foundInTgtAcr.Count -eq 1) {
            LogInfo "Image '$imageName' with tag '$imageTag' already available in acr '$TgtAcrName'"
        }
        else {
            LogInfo -Message "Login to '$SrcAcrName'"
            $SrcAcrPwd | docker login "$SrcAcrName.azurecr.io" --username $SrcAcrName --password-stdin | Out-Null

            $SourceImage = "$($SrcAcrName).azurecr.io/$($imageName):$($imageTag)"
            LogInfo -Message "Pulling image '$SourceImage'..."
            docker pull $SourceImage
            $TargetImage = "$($TgtAcrName).azurecr.io/$($imageName):$($imageTag)"
            docker tag $SourceImage $TargetImage

            LogInfo -Message "Login to '$TgtAcrName'"
            $TgtAcrPwd | docker login "$TgtAcrName.azurecr.io" --username $TgtAcrName --password-stdin | Out-Null

            LogInfo -Message "Pushing image '$TargetImage'..."
            docker push $TargetImage

            LogInfo -Message "Clearing image '$imageName' from disk"
            $targetImageId = $(docker images -q --filter "reference=$TargetImage")
            if ($targetImageId) {
                docker image rm $targetImageId -f
            }
            $sourceImageId = $(docker images -q --filter "reference=$SourceImage")
            if ($sourceImageId) {
                docker image rm $sourceImageId -f
            }
        }

        $totalImagesSynced++
        LogInfo -Message "Synced $totalImagesSynced of $($infraImages.images.Count) images"
    }
}


UsingScope("Restoring svc images") {
    $totalImagesSynced = 0

    $svcImages.images | ForEach-Object {
        $imageName = $_.name
        $imageTag = $_.tag
        $foundInTgtAcr = $imagesInTargetAcr | Where-Object { $_.name -eq $imageName -and $_.tag -eq $imageTag }
        if ($null -ne $foundInTgtAcr -and $foundInTgtAcr.Count -eq 1) {
            LogInfo "Image '$imageName' with tag '$imageTag' already available in acr '$TgtAcrName'"
        }
        else {
            LogInfo -Message "Login to '$SrcAcrName'"
            $SrcAcrPwd | docker login "$SrcAcrName.azurecr.io" --username $SrcAcrName --password-stdin | Out-Null

            $SourceImage = "$($SrcAcrName).azurecr.io/$($imageName):$($imageTag)"
            LogInfo -Message "Pulling image '$SourceImage'..."
            docker pull $SourceImage
            $TargetImage = "$($TgtAcrName).azurecr.io/$($imageName):$($imageTag)"
            docker tag $SourceImage $TargetImage

            LogInfo -Message "Login to '$TgtAcrName'"
            $TgtAcrPwd | docker login "$TgtAcrName.azurecr.io" --username $TgtAcrName --password-stdin | Out-Null

            LogInfo -Message "Pushing image '$TargetImage'..."
            docker push $TargetImage

            LogInfo -Message "Clearing image '$imageName' from disk"
            $targetImageId = $(docker images -q --filter "reference=$TargetImage")
            if ($targetImageId) {
                docker image rm $targetImageId -f
            }
            $sourceImageId = $(docker images -q --filter "reference=$SourceImage")
            if ($sourceImageId) {
                docker image rm $sourceImageId -f
            }
        }

        $totalImagesSynced++
        LogInfo -Message "Synced $totalImagesSynced of $($svcImages.images.Count) images"
    }
}
