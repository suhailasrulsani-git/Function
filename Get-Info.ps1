function Get-info {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SupportID
    )
    $Domains = @("abc.net", "zone1.abc.net", "zone2.abc.net", "zone3.abc.net")
    $InfoFound = $false
    $PSIDName = $null
    $Linemanager = $null
    $LinemanagerName = $null
    if ($SupportID -notlike "svc.*") {
        $ID = $SupportID | ForEach-Object { $_ -replace ("a\.efa\.|\.dev|a\.ea\.|a\.dca\.|a\.sa\.|o\.|a\.psrm\.|a\.t3\.|a\.mstfa\.|a\.exofa\.|a\.exot3\.|a\.sms\.|a\.ga\.", "") }
        $ID = $ID | ForEach-Object { $_ -replace ("a\.dp|a\.exquar\.|a\.expsrm\.", "") }
        foreach ($Domain in $Domains) {
            try {
                $Info = Get-ADUser -Identity $ID -Server $Domain -Properties DisplayName,Manager
                $InfoFound = $true

                if ($Info.DisplayName) {
                    $PSIDName = $Info.DisplayName
                    if ([string]::IsNullOrEmpty($PSIDName)) {
                        $PSIDName = $false
                    }
                }

                if ($info.Manager) {
                    $Linemanager = $info.Manager
                    $Linemanager = $Linemanager | Select-String -Pattern "CN=([^,]+)" -AllMatches
                    $Linemanager = $Linemanager.Matches[0].Groups[1].Value

                    if ([string]::IsNullOrEmpty($Linemanager)) {
                        $Linemanager = $false
                    }

                    elseif ($Linemanager) {
                        foreach ($Domain in $Domains) {
                            try {
                                $Info = Get-ADUser -Identity $Linemanager -Server $Domain -Properties DisplayName

                                if ($Info.DisplayName) {
                                    $LinemanagerName = $Info.DisplayName
                                    if ([string]::IsNullOrEmpty($LinemanagerName)) {
                                        $LinemanagerName = $false
                       
                                    }

                                }
                            }

                            catch {
                                continue
                            }
                            
                        }
                    }
                }
                Break
            }

            catch {
                Continue
            }
        }

        if (-not $InfoFound) {
            return [PSCustomObject]@{
                SupportID = $SupportID
                PSID = $ID
                PSIDName = "ERROR"
                LineManager = "ERROR"
                LineManagerName = "ERROR"
            }
            Break
        }

        return [PSCustomObject]@{
            SupportID = $SupportID
            PSID = $ID
            PSIDName = $PSIDName
            LineManager = $Linemanager
            LineManagerName = $LinemanagerName
        }
    }

    elseif ($SupportID -like "svc.*") {
        
        foreach ($Domain in $Domains) {
            try {
                $Info = Get-ADUser -Identity $SupportID -Server $Domain -Properties ExtensionAttribute1
                if ($Info.ExtensionAttribute1) {
                    $Linemanager = $Info.ExtensionAttribute1

                    if ([string]::IsNullOrEmpty($Linemanager)) {
                        $Linemanager = $false
                        $LinemanagerName = $false
                    }

                    elseif ($Linemanager) {
                        foreach ($Domain in $Domains) {
                            try {
                                $Info = Get-ADUser -Identity $Linemanager -Server $Domain -Properties DisplayName

                                if ($info.DisplayName) {
                                    $LinemanagerName = $info.DisplayName

                                    if ([string]::IsNullOrEmpty($info.DisplayName)) {
                                        $LinemanagerName = $false
                                    }
                                }
                            }

                            catch {
                                continue
                            }
                        }
                    }
                    
                }
                Break
            }

            catch {
                Continue
            }
            
        }

        return [PSCustomObject]@{
            SupportID = $SupportID
            PSID = $false
            PSIDName = $false
            LineManager = $Linemanager
            LineManagerName = $LinemanagerName
        }
    }
}

Get-info -SupportID "o.2003686"
Get-info -SupportID "svc.svrmonitor.002"
