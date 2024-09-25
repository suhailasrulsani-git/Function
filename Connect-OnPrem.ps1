Function Connect-OnPrem {
    try {

        $Connection = Get-PSSession | Where-Object { $_.ConfigurationName -eq "Microsoft.Exchange" } -ErrorAction Stop | Select-Object -ExpandProperty State
        if ($Connection -eq "Opened") {
            "Connected to Exchange OnPrem"
        }

        else {
            $PathFound = $env:ExchangeInstallPath + "bin\RemoteExchange.ps1"
            if (Test-Path $PathFound) {
                $ExchangeScript = $PathFound
                . $ExchangeScript
                Connect-ExchangeServer -auto
                Set-ADServerSettings -ViewEntireForest $true
                Clear-Host
                "Connected to Exchange OnPrem"
            }

            else {
                "Failed to connect to Exchange OnPrem"
            }
        }
    }
    catch {
        "Failed to connec to Exchange OnPrem"
    }
}
