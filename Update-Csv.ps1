function Update-Csv {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        # Column used to find the row, example: SamAccountName
        [Parameter(Mandatory)]
        [string]$MatchColumn,

        # Value used to find the row, example: 2003686
        [Parameter(Mandatory)]
        [string]$MatchValue,

        # Column you want to update
        [Parameter(Mandatory)]
        [string]$UpdateColumn,

        # New value for that column
        [Parameter(Mandatory)]
        [AllowNull()]
        [string]$NewValue,

        # Optional: return updated row
        [switch]$PassThru
    )

    if (-not (Test-Path $Path)) {
        throw "CSV file not found: $Path"
    }

    $csv = Import-Csv -Path $Path

    if (-not $csv) {
        throw "CSV file is empty: $Path"
    }

    $columns = $csv[0].PSObject.Properties.Name

    if ($MatchColumn -notin $columns) {
        throw "Match column '$MatchColumn' not found in CSV."
    }

    if ($UpdateColumn -notin $columns) {
        throw "Update column '$UpdateColumn' not found in CSV."
    }

    $matchedRows = @($csv | Where-Object { $_.$MatchColumn -eq $MatchValue })

    if ($matchedRows.Count -eq 0) {
        throw "No row found where $MatchColumn = '$MatchValue'."
    }

    if ($matchedRows.Count -gt 1) {
        throw "More than one row found where $MatchColumn = '$MatchValue'. Update stopped to avoid changing multiple rows."
    }

    $matchedRows[0].$UpdateColumn = $NewValue

    $csv | Export-Csv -Path $Path -NoTypeInformation

    if ($PassThru) {
        return $matchedRows[0]
    }
}
