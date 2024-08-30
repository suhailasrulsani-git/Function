Function Get-ObjectLocation {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Object
    )

    $Domains = @("abc.net","zone1.abc.net","zone2.abc.net","zone3.abc.net")
    foreach ($Domain in $Domains) {
        Try {
            $Info = Get-ADObject -Filter "samaccountname -eq '$Object'" -Server $Domain -Properties homeMDB,targetAddress -ErrorAction Stop
            if ($Info) {
                if ($Info.homeMDB) {
                    return "OnPrem"
                }

                elseif ($Info.targetAddress -like "*mail.onmicrosoft.com*") {
                    return "Online"
                }

                else {
                    return "NoMailbox"
                }
            }
        }

        Catch {
            Continue
        }
    }

    if ([string]::IsNullOrEmpty($Info)) {
        return "ERROR"
    }
}
