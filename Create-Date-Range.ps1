Function Create-Date-Range {
    param (
        $StartDate,
        $EndDate,
        $Minutes
    )
    $StartDate       = [datetime]$StartDate
    $EndDate         = [datetime]$EndDate
    $OriginalEndDate = $EndDate

    $RangeCount   = [math]::Ceiling(($EndDate - $StartDate).TotalMinutes / $Minutes)
    $Result       = @()
    $CurrentStart = $StartDate

    foreach ($RangeNumber in 1..$RangeCount) {
        $CurrentEnd = $CurrentStart.AddMinutes($Minutes)

        if ($CurrentEnd -gt $OriginalEndDate) {
            $CurrentEnd = $OriginalEndDate
        }

        # Skip zero-length ranges
        if ($CurrentEnd -le $CurrentStart) { continue }

        $RangeMinutes = ($CurrentEnd - $CurrentStart).TotalMinutes

        $Result += [PSCustomObject]@{
            RangeNumber  = $RangeNumber
            StartDate    = $CurrentStart
            EndDate      = $CurrentEnd
            RangeMinutes = $RangeMinutes
        }

        $CurrentStart = $CurrentEnd
    }

    $Result
}
