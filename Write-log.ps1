function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet("Information", "Error")][string]$Label = "Information",
        [Parameter(Mandatory=$false)][string]$LogFile = "$CurrentPath\Log.txt"
    )

    # Get the current timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Format the log message with the timestamp and label
    $logMessage = "[$timestamp] [$Label] $Message"

    # Write the message to the console
    Write-Host $logMessage

    # Append the message to the log file
    Add-Content -Path $LogFile -Value $logMessage
}
