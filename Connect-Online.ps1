Function Connect-Online {
    try {
        $Connection = Get-ConnectionInformation | Select-Object -ExpandProperty State -ErrorAction Stop
        if ($Connection -eq "Connected") {
            return "Connected to Online"
        }

        else {
            Connect-ExchangeOnline -Prefix O365 -ErrorAction Stop
            Clear-Host
            return "Connected to Online"
        }
    }

    catch {
        return "Failed to connect to Online"
    } 
}
