$CSVFiles = Get-ChildItem -Path .\ -Filter *.csv
$ALLCSVData = @()
Foreach ($SingleCSVFiles in $CSVFiles) {
    $CSVData = Import-Csv $SingleCSVFiles
    $ALLCSVData += $CSVData
}
$ALLCSVData | Export-Csv -Path .\Final.csv -NoTypeInformation -Encoding UTF8 -Force
