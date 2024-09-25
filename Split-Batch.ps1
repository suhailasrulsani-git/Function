Function Split-Batch {
    param (
        [Parameter(Mandatory = $true)]
        $Object,

        [Parameter(Mandatory = $true)]
        [int]$Number
    )

    $BatchSize = [math]::Ceiling($Object.Count / $Number)
    $UserBatches = $Object | ForEach-Object -Begin {
        $Batch = @()
        $BatchNumber = 0
    } -Process {
        $Batch += $_
        if ($Batch.Count -eq $BatchSize) {
            $BatchNumber++
            [PSCustomObject]@{
                Batch       = $Batch
                BatchNumber = $BatchNumber
            }
            $Batch = @()
        }
    } -End {
        if ($Batch.Count) {
            $BatchNumber++
            [PSCustomObject]@{
                Batch       = $Batch
                BatchNumber = $BatchNumber
            }
        }
    }
    Return $UserBatches
}

Split-Batch -Object $Users -Number 2
