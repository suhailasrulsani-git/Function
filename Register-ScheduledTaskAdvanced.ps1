function Register-ScheduledTaskAdvanced {
    <#
    .SYNOPSIS
        Registers a new scheduled task in Windows Task Scheduler.
    
    .DESCRIPTION
        Creates and registers a scheduled task with customizable triggers, actions, and settings.
        Supports various trigger types and execution options.
    
    .PARAMETER TaskName
        The name of the scheduled task.
    
    .PARAMETER TaskPath
        The folder path where the task will be stored (default: "\").
    
    .PARAMETER Description
        Description of the task.
    
    .PARAMETER ScriptPath
        Path to the script or executable to run.
    
    .PARAMETER Arguments
        Arguments to pass to the script/executable.
    
    .PARAMETER TriggerType
        Type of trigger: Daily, Weekly, AtStartup, AtLogon, Once, OnIdle.
    
    .PARAMETER StartTime
        Time when the task should start (for time-based triggers).
    
    .PARAMETER DaysInterval
        Number of days between runs (for Daily trigger).
    
    .PARAMETER DaysOfWeek
        Days of the week to run (for Weekly trigger). E.g., "Monday,Wednesday,Friday"
    
    .PARAMETER RunAsUser
        Username to run the task as (default: SYSTEM).
    
    .PARAMETER RunLevel
        Run with highest privileges (Highest) or limited privileges (Limited).
    
    .PARAMETER Hidden
        Hide the task in Task Scheduler UI.

    .PARAMETER RunWhetherLoggedOn
        Run the task whether the user is logged on or not. Only applicable for named user accounts.
        Service accounts (SYSTEM, LOCAL SERVICE, NETWORK SERVICE) ignore this flag.

    .PARAMETER Password
        Plain text password for the RunAsUser account. Only used when RunWhetherLoggedOn is set
        and RunAsUser is not a service account.
    
    .EXAMPLE
        Register-ScheduledTaskAdvanced -TaskName "BackupScript" -ScriptPath "C:\Scripts\Backup.ps1" -TriggerType Daily -StartTime "02:00" -Description "Daily backup job"
    
    .EXAMPLE
        Register-ScheduledTaskAdvanced -TaskName "StartupScript" -ScriptPath "C:\Scripts\Startup.ps1" -TriggerType AtStartup -RunAsUser "SYSTEM" -RunLevel Highest
    
    .EXAMPLE
        Register-ScheduledTaskAdvanced -TaskName "WeeklyReport" -ScriptPath "C:\Scripts\Report.ps1" -TriggerType Weekly -DaysOfWeek "Monday,Friday" -StartTime "09:00"

    .EXAMPLE
        Register-ScheduledTaskAdvanced -TaskName "UserTask" -ScriptPath "C:\Scripts\Task.ps1" -TriggerType Daily -StartTime "08:00" -RunAsUser "DOMAIN\john" -RunWhetherLoggedOn -Password "MyPassword123"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,
        
        [Parameter(Mandatory = $false)]
        [string]$TaskPath = "\",
        
        [Parameter(Mandatory = $false)]
        [string]$Description = "",
        
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Arguments = "",
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("Daily", "Weekly", "AtStartup", "AtLogon", "Once", "OnIdle")]
        [string]$TriggerType,
        
        [Parameter(Mandatory = $false)]
        [string]$StartTime,
        
        [Parameter(Mandatory = $false)]
        [int]$DaysInterval = 1,
        
        [Parameter(Mandatory = $false)]
        [string]$DaysOfWeek,
        
        [Parameter(Mandatory = $false)]
        [string]$RunAsUser = "SYSTEM",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Highest", "Limited")]
        [string]$RunLevel = "Limited",
        
        [Parameter(Mandatory = $false)]
        [switch]$Hidden,

        [Parameter(Mandatory = $false)]
        [switch]$RunWhetherLoggedOn,

        [Parameter(Mandatory = $false)]
        [string]$Password
    )
    
    try {
        Write-Host "Creating scheduled task: $TaskName" -ForegroundColor Cyan
        
        # Create the task folder if it doesn't exist
        if ($TaskPath -ne "\") {
            try {
                $schedule = New-Object -ComObject Schedule.Service
                $schedule.Connect()
                $rootFolder = $schedule.GetFolder("\")
                
                # Split the path and create nested folders
                $folders = $TaskPath.Trim('\').Split('\')
                $currentPath = "\"
                
                foreach ($folder in $folders) {
                    if ($folder) {
                        $nextPath = if ($currentPath -eq "\") { "\$folder" } else { "$currentPath\$folder" }
                        
                        try {
                            $schedule.GetFolder($nextPath) | Out-Null
                            Write-Host "Folder already exists: $nextPath" -ForegroundColor Gray
                        }
                        catch {
                            try {
                                $parentFolder = $schedule.GetFolder($currentPath)
                                $parentFolder.CreateFolder($folder) | Out-Null
                                Write-Host "Created folder: $nextPath" -ForegroundColor Green
                            }
                            catch {
                                Write-Warning "Could not create folder $nextPath : $_"
                            }
                        }
                        
                        $currentPath = $nextPath
                    }
                }
            }
            catch {
                Write-Warning "Error checking/creating task folder: $_"
            }
            finally {
                if ($schedule) {
                    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($schedule) | Out-Null
                }
            }
        }
        
        # Create the action
        if ($Arguments) {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $Arguments"
        }
        else {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        }
        
        # Create the trigger based on type
        $trigger = $null
        switch ($TriggerType) {
            "Daily" {
                if (-not $StartTime) {
                    throw "StartTime is required for Daily trigger"
                }
                $trigger = New-ScheduledTaskTrigger -Daily -At $StartTime -DaysInterval $DaysInterval
            }
            "Weekly" {
                if (-not $StartTime) {
                    throw "StartTime is required for Weekly trigger"
                }
                if (-not $DaysOfWeek) {
                    throw "DaysOfWeek is required for Weekly trigger"
                }
                $daysArray = $DaysOfWeek -split ','
                $trigger = New-ScheduledTaskTrigger -Weekly -At $StartTime -DaysOfWeek $daysArray
            }
            "AtStartup" {
                $trigger = New-ScheduledTaskTrigger -AtStartup
            }
            "AtLogon" {
                $trigger = New-ScheduledTaskTrigger -AtLogon
            }
            "Once" {
                if (-not $StartTime) {
                    throw "StartTime is required for Once trigger"
                }
                $trigger = New-ScheduledTaskTrigger -Once -At $StartTime
            }
            "OnIdle" {
                $trigger = New-ScheduledTaskTrigger -AtStartup
                Write-Warning "OnIdle trigger requires additional configuration through Task Scheduler UI"
            }
        }
        
        # Determine LogonType
        $serviceAccounts = @("SYSTEM", "LOCAL SERVICE", "NETWORK SERVICE",
                             "NT AUTHORITY\SYSTEM", "NT AUTHORITY\LOCAL SERVICE", "NT AUTHORITY\NETWORK SERVICE")

        if ($RunWhetherLoggedOn) {
            if ($RunAsUser -in $serviceAccounts) {
                Write-Warning "RunWhetherLoggedOn is redundant for service accounts like '$RunAsUser'. Using ServiceAccount logon type."
                $logonType = "ServiceAccount"
            } else {
                $logonType = "Password"
            }
        } else {
            $logonType = "ServiceAccount"
        }

        $principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType $logonType -RunLevel $RunLevel
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        if ($Hidden) {
            $settings.Hidden = $true
        }
        
        # Build base task parameters
        $taskParams = @{
            TaskName  = $TaskName
            TaskPath  = $TaskPath
            Action    = $action
            Trigger   = $trigger
            Principal = $principal
            Settings  = $settings
        }
        
        if ($Description) {
            $taskParams.Add("Description", $Description)
        }
        
        # Register the task — use User/Password parameter set if credentials provided
        if ($Password -and $logonType -eq "Password") {
            $taskParamsWithCred = $taskParams.Clone()
            $taskParamsWithCred.Remove("Principal")
            Register-ScheduledTask @taskParamsWithCred -User $RunAsUser -Password $Password -RunLevel $RunLevel -Force | Out-Null
        } else {
            Register-ScheduledTask @taskParams -Force | Out-Null
        }
        
        Write-Host "Successfully registered task: $TaskName" -ForegroundColor Green
        Write-Host "Task Path: $TaskPath$TaskName" -ForegroundColor Gray
        
        # Display task information
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        if ($task) {
            Write-Host "`nTask Details:" -ForegroundColor Yellow
            Write-Host "  State: $($task.State)" -ForegroundColor Gray
            Write-Host "  Trigger Type: $TriggerType" -ForegroundColor Gray
            Write-Host "  Run Level: $RunLevel" -ForegroundColor Gray
        }
        
        return $task
    }
    catch {
        Write-Host "Error registering scheduled task: $_" -ForegroundColor Red
        throw
    }
}
