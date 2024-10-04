Function Get-Sam-From-Email {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Object
    )
$Domains = @("abc.net", "zone1.abc.net", "zone2.abc.net", "zone3.abc.net")
    Foreach ($Domain in $Domains) {
        $InfoFound =$false
        Try {
            $Info = Get-ADObject -Filter "mail -eq '$Object'" -Server $Domain -Properties SamAccountName

            if (![string]::IsNullOrEmpty($Info)) {
                $InfoFound = $true
                Break
            }
        }

        Catch {
            Continue
        }
        
    }

    If ($InfoFound -eq $false) {
        return "ERROR"
    }

    else {
        return $Info.SamAccountName
    }
}
