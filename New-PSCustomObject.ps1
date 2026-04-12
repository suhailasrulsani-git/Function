Function New-PSCustomObject {
    param (
        [ValidateNotNullOrEmpty()]
        [string[]]$Properties
    )

    $hash = [ordered]@{}
    foreach ($c in $Properties) {
        $hash[$c] = $null
    }

    return [PSCustomObject]$hash
}
