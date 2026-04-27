function Add-ContentSafe {
    param(
        [string]$Path,
        [string]$Content,
        [int]$Retry = 20
    )

    $attempt = 0

    while ($attempt -lt $Retry) {
        try {
            Add-Content -Path $Path -Value $Content -ErrorAction Stop
            return
        }
        catch {
            $attempt++
            $wait = Get-Random -Minimum 100 -Maximum 500
            Start-Sleep -Milliseconds $wait
        }
    }
}
