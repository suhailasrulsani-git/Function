Function Check-Group-Or-User {
    param (
        [Parameter(Mandatory=$true)]
        $Object
    )
    
    $Domains = @("abc.net","zone1.abc.net","zone2.abc.net","zone3.abc.net")
    Foreach ($SingleDomain in $Domains) {
        $InfoFound = $false
        $Info = Get-ADObject -Filter "Name -eq '$Object'" -Server $SingleDomain
        if (![string]::IsNullOrEmpty($Info)) {
            $InfoFound = $true
            Break
        }

        Else {
            $InfoFound = $false
            Break
        }
    }

    If (-not($InfoFound)) {
        Return "ERROR"
    }

    Else {
        Return $Info.ObjectClass
    }
}
