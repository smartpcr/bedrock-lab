function GetImagesWithTags() {
    param(
        [string]$AcrName,
        [string]$SubscriptionName
    )

    $imageDetails = New-Object System.Collections.ArrayList

    UsingScope("login") {
        $azAccount = LoginAzureAsUser -SubscriptionName $SubscriptionName
        LogStep -Message "Logged in as user '$($azAccount.name)'"
    }

    UsingScope("Retrieving acr pwd") {
        $AcrName = $AcrName
        az acr login -n $AcrName | Out-Null
        az acr update -n $AcrName --admin-enabled true | Out-Null
        $AcrCredential = az acr credential show -n $AcrName | ConvertFrom-Json
        $AcrPwd = $AcrCredential.passwords[0].value
        $AcrAuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($AcrName):$($AcrPwd)"))
        LogInfo -Message "acr auth header: $AcrAuthHeader"
    }

    UsingScope("Get all repositories in '$AcrName'") {
        $AuthHeaderValue = "Basic $AcrAuthHeader"
        # docker login $LoginServer -u $SpnAppId -p $AcrPwd
        $imageCatalog = Invoke-RestMethod -Headers @{Authorization = $AuthHeaderValue } -Method Get -Uri "https://$AcrName.azurecr.io/v2/_catalog"
        $repositories = $imageCatalog.repositories
        if ($null -ne $repositories) {
            LogInfo -Message "Total of $($repositories.Count) reposities found"
        }
        else {
            LogInfo -Message "Total of 0 reposities found"
        }
    }

    if ($null -ne $repositories -and $repositories.Count -gt 0) {
        UsingScope("Scan repository in '$AcrName'") {
            $totalImagesScanned = 0
            $repositories | ForEach-Object {
                $RepositoryName = $_
                LogInfo -Message "Getting latest image tag"
                $imageTags = Invoke-RestMethod -Headers @{Authorization = $AuthHeaderValue } -Method Get -Uri "https://$AcrName.azurecr.io/v2/$($RepositoryName)/tags/list"
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

                $imageDetails.Add(@{
                        name = $RepositoryName
                        tag  = $tag
                    }) | Out-Null
                $totalImagesScanned++
                LogStep -Message "Scanned $totalImagesScanned of $($repositories.Count) repositories"
            }

            return $imageDetails
        }
    }
    else {
        return $imageDetails
    }
}