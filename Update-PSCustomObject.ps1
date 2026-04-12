Function Update-PSCustomObject {
    param (
        $CsvFile,
        $MasterProperty,
        $MasterKey,
        $Property,
        $Value
    )

    $ImportCSV = Import-Csv -Path $CsvFile
    $MainRow = $ImportCSV | Where-Object { $_.$MasterProperty -eq $MasterKey }
    $MainRow.$Property = $Value
    $ImportCSV | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
}

Update-PSCustomObject -CsvFile .\test.csv -MasterProperty "Id" -MasterKey "S0000002" -Property "status2" -Value "Pending"
