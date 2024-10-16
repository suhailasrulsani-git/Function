Function Get-MemberOf {
    param (
        [Parameter(Mandatory = $true)]
        $Object
    )

    $Domains = @("abc.net", "zone1.abc.net", "zone2.abc.net", "zone3.abc.net")
    Foreach ($SingleDomain in $Domains) {
        $InfoFound = $false
        $Info = Get-ADGroup -Filter "Name -eq '$Object'" -Server $SingleDomain -Properties MemberOf
        if (![string]::IsNullOrEmpty($Info)) {
            $InfoFound = $true
            Break
        }
    }

    If (-not($InfoFound)) {
        return "ERROR"
    }

    Else {
        $MemberOf1 = $Info.MemberOf
        $MemberOf = @()
        Foreach ($M in $MemberOf1) {
            $M = $M | Select-String -Pattern "CN=([^,]+)" -AllMatches
            $M = $M.Matches[0].Groups[1].Value
            $MemberOf += $M      
        }
        return $MemberOf
    }
}
