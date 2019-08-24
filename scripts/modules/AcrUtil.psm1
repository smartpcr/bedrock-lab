function GetImagesWithTags() {
    param(
        [string]$AcrName,
        [string]$SubscriptionName
    )

    UsingScope("login") {
        $azAccount = LoginAzureAsUser -SubscriptionName $SubscriptionName
        LogStep -Message "Logged in as user '$($azAccount.name)'"
    }

    UsingScope("Retrieving acr pwd") {
        $SrcAcrName = $AcrName
        az acr login -n $SrcAcrName | Out-Null
        az acr update -n $SrcAcrName --admin-enabled true | Out-Null
        $SrcAcrCredential = az acr credential show -n $SrcAcrName | ConvertFrom-Json
        $SrcAcrPwd = $SrcAcrCredential.passwords[0].value
        $SrcAcrAuthHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($SrcAcrName):$($SrcAcrPwd)"))
        LogInfo -Message "acr auth header: $SrcAcrAuthHeader"
    }

    UsingScope("Get all images from '$SrcAcrName'") {
        # docker login $LoginServer -u $SpnAppId -p $SrcAcrPwd
        $imageCatalog = Invoke-RestMethod -Headers @{Authorization = ("Basic {0}" -f $SrcAcrAuthHeader) } -Method Get -Uri "https://$SrcAcrName.azurecr.io/v2/_catalog"
        $repositories = $imageCatalog.repositories
        LogInfo -Message "Total of $($repositories.Count) reposities found"
    }

    UsingScope("Sync docker images from '$SrcAcrName' to '$TargetAcrName'") {
        $totalImagesScanned = 0
        $imageDetails = New-Object System.Collections.ArrayList

        $repositories | ForEach-Object {
            $RepositoryName = $_

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