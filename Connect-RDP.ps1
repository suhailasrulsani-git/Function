function Connect-RDP {
    <#
    .SYNOPSIS
        Opens an RDP session to a remote server using provided credentials.

    .DESCRIPTION
        Temporarily registers credentials in Windows Credential Manager,
        launches an mstsc RDP session, then immediately removes the stored
        credential to avoid persistence.

    .PARAMETER Server
        Hostname or IP address of the target server.

    .PARAMETER Username
        Plain text username (e.g. "DOMAIN\user" or ".\localuser").

    .PARAMETER Password
        Plain text password for the account.

    .EXAMPLE
        Connect-RDP -Server "192.168.1.10" -Username "dev\admin" -Password "mypassword"

    .EXAMPLE
        Connect-RDP -Server "devbox01" -Username ".\administrator" -Password "mypassword"
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

    try {
        # Register credential temporarily in Windows Credential Manager
        cmdkey /generic:$Server /user:$Username /pass:$Password | Out-Null

        # Launch RDP session
        mstsc /v:$Server

        Write-Host "RDP session launched for '$Server'." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to launch RDP session: $_"
    }
    finally {
        # Always clean up — even if mstsc fails
        cmdkey /delete:$Server | Out-Null
        Write-Verbose "Credential for '$Server' removed from Credential Manager."
    }
}
