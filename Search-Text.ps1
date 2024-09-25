Function Search-Text {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [Parameter(Mandatory = $true)]
        $path

    )

    $a = Get-ChildItem -Path $path -Filter *.ps1 -Recurse #| Select-Object -First 10 #-Recurse
    $fullpath = $a.FullName

    $results = foreach ($b in $fullpath) {
        $c = Select-String -Path $b -Pattern $Text -SimpleMatch

        if ($c) {
        
            [PSCustomObject]@{
                File     = $c.Filename
                FilePath = $b
                Line     = $c.LineNumber
                #Content = $c.Line
            }
        }
    }

    return $results
}

Search-Text -Text "Instance" -path ".\"
