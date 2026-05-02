function Start-Parallel {
    param (
        [int]$Number,
        [int]$Batch,
        [string]$MainListPath = ".",
        [string]$OutputFolder = ".",
        [string]$CurrentPath,
        [object[]]$ImportModule,
        [string[]]$DotSourceScript,

        # Mandatory: logging folder (local or UNC)
        [Parameter(Mandatory = $true)]
        [string]$LogFolder,

        # Mandatory: timeout in minutes applied equally to all batches
        [Parameter(Mandatory = $true)]
        [int]$TimeoutMinutes,

        # Runs once per spawned session before the loop (module load, connect, etc.)
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$SetupBlock,

        # Runs once per item — wrapper owns the loop, progress, reconnect, export
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ItemBlock,

        # Reconnect interval — re-runs SetupBlock every N items. 0 = disabled. Default 1000.
        [int]$ReconnectInterval = 1000
    )

    # -------------------------------------------------------------------------
    # INNER FUNCTION: Split-CsvByBatchCount
    # -------------------------------------------------------------------------
    function Split-CsvByBatchCount {
        param (
            [string]$InputFile,
            [int]$BatchSize,
            [string]$OutputFolder
        )

        if (!(Test-Path $InputFile)) {
            throw "Input file '$InputFile' not found."
        }

        if (!(Test-Path $OutputFolder)) {
            New-Item -ItemType Directory -Path $OutputFolder | Out-Null
        }

        $items      = Import-Csv -Path $InputFile
        $totalItems = $items.Count

        if ($BatchSize -lt 1) {
            throw "BatchSize must be at least 1."
        }

        $TotalBatches = [math]::Ceiling($totalItems / $BatchSize)

        Write-Host "Total items: $totalItems | Batch size: $BatchSize | Total batches needed: $TotalBatches" -ForegroundColor Cyan

        for ($i = 0; $i -lt $TotalBatches; $i++) {
            $startIndex = $i * $BatchSize
            $endIndex   = [math]::Min($startIndex + $BatchSize - 1, $totalItems - 1)

            if ($startIndex -gt $endIndex) { break }

            $batchItems = $items[$startIndex..$endIndex]
            $batchFile  = Join-Path $OutputFolder ("Batch{0}.csv" -f ($i + 1))
            $batchItems | Export-Csv -Path $batchFile -NoTypeInformation -Encoding UTF8

            Write-Host "  Batch $($i + 1): $($batchItems.Count) items" -ForegroundColor Gray
        }

        return $TotalBatches
    }

    # -------------------------------------------------------------------------
    # INNER FUNCTION: Get-ImportModuleCommands
    # -------------------------------------------------------------------------
    function Get-ImportModuleCommands {
        param ([object[]]$Modules)

        if ($null -eq $Modules -or $Modules.Count -eq 0) { return "" }

        $commands = @()

        foreach ($module in $Modules) {
            if ($module -is [string]) {
                $commands += "Import-Module '$module' -Force"
            }
            elseif ($module -is [hashtable]) {
                $modulePath = $module.Path
                $params     = @()

                foreach ($key in $module.Keys) {
                    if ($key -ne 'Path') {
                        $value = $module[$key]
                        if ($value -is [string])   { $params += "-$key '$value'" }
                        elseif ($value -is [bool]) { if ($value) { $params += "-$key" } }
                        else                        { $params += "-$key $value" }
                    }
                }

                $command = "Import-Module '$modulePath'"
                if ($params.Count -gt 0) { $command += " " + ($params -join ' ') }
                $commands += $command
            }
        }

        return ($commands -join "`n")
    }

    # -------------------------------------------------------------------------
    # INNER FUNCTION: Get-DotSourceCommands
    # -------------------------------------------------------------------------
    function Get-DotSourceCommands {
        param ([string[]]$Scripts)

        if ($null -eq $Scripts -or $Scripts.Count -eq 0) { return "" }

        $commands = @()
        foreach ($script in $Scripts) {
            $commands += ". '$script' *> `$null"
        }
        return ($commands -join "`n")
    }

    # -------------------------------------------------------------------------
    # INNER FUNCTION: Write-Log  (main session log)
    # -------------------------------------------------------------------------
    function Write-Log {
        param (
            [string]$Message,
            [string]$Level = "INFO",
            [string]$LogPath
        )

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line      = "[$timestamp] [$Level] $Message"

        if ($LogPath) {
            Add-Content -Path $LogPath -Value $line -Encoding UTF8
        }

        switch ($Level) {
            "INFO"    { Write-Host $line -ForegroundColor Cyan    }
            "WARN"    { Write-Host $line -ForegroundColor Yellow  }
            "ERROR"   { Write-Host $line -ForegroundColor Red     }
            "SUCCESS" { Write-Host $line -ForegroundColor Green   }
            default   { Write-Host $line }
        }
    }

    # -------------------------------------------------------------------------
    # INNER FUNCTION: Read-ProgressFile  (safe read, handles file lock)
    # -------------------------------------------------------------------------
    function Read-ProgressFile {
        param ([string]$Path)

        if (-not (Test-Path $Path)) { return $null }

        try {
            $lines  = Get-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
            $result = @{ Current = 0; Total = 0; CurrentObject = "" }

            foreach ($line in $lines) {
                if ($line -match '^Current=(\d+)$')          { $result.Current       = [int]$Matches[1] }
                elseif ($line -match '^Total=(\d+)$')        { $result.Total         = [int]$Matches[1] }
                elseif ($line -match '^CurrentObject=(.+)$') { $result.CurrentObject = $Matches[1] }
            }

            return $result
        }
        catch {
            return $null
        }
    }

    # -------------------------------------------------------------------------
    # INNER FUNCTION: Format-ETA
    # -------------------------------------------------------------------------
    function Format-ETA {
        param (
            [int]$Current,
            [int]$Total,
            [TimeSpan]$Elapsed
        )

        if ($Current -le 0) { return "Calculating..." }

        $itemsRemaining = $Total - $Current
        $secondsPerItem = $Elapsed.TotalSeconds / $Current
        $secondsLeft    = $secondsPerItem * $itemsRemaining
        $eta            = (Get-Date).AddSeconds($secondsLeft)
        $remaining      = [TimeSpan]::FromSeconds($secondsLeft)
        $formatted      = ""

        if ($remaining.Hours   -gt 0) { $formatted += "$($remaining.Hours)h "   }
        if ($remaining.Minutes -gt 0) { $formatted += "$($remaining.Minutes)m " }
        $formatted += "$($remaining.Seconds)s"

        return "$formatted (ETA: $(Get-Date $eta -Format 'HH:mm:ss'))"
    }

    # =========================================================================
    # SETUP
    # =========================================================================

    if (!(Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder | Out-Null
    }

    $ComputerPrefix = $env:COMPUTERNAME
    $MainLogPath    = Join-Path $LogFolder "$ComputerPrefix-MainSession.log"

    Write-Log -Message "Start-Parallel initiated."                    -Level INFO -LogPath $MainLogPath
    Write-Log -Message "OutputFolder       : $OutputFolder"           -Level INFO -LogPath $MainLogPath
    Write-Log -Message "LogFolder          : $LogFolder"              -Level INFO -LogPath $MainLogPath
    Write-Log -Message "Sessions           : $Number"                 -Level INFO -LogPath $MainLogPath
    Write-Log -Message "Timeout            : $TimeoutMinutes minutes" -Level INFO -LogPath $MainLogPath
    Write-Log -Message "ReconnectInterval  : $ReconnectInterval"      -Level INFO -LogPath $MainLogPath

    # Determine batch size
    if ($Batch -gt 0) {
        $BatchSize = $Batch
    }
    else {
        $items     = Import-Csv -Path $MainListPath
        $BatchSize = [math]::Ceiling($items.Count / $Number)
    }

    # Step 1: Split CSV into batches
    Write-Log -Message "=== Splitting CSV into batches ===" -Level INFO -LogPath $MainLogPath
    $TotalBatches = Split-CsvByBatchCount -InputFile $MainListPath -BatchSize $BatchSize -OutputFolder $OutputFolder

    $AllBatchFiles    = Get-ChildItem -Path $OutputFolder -Filter Batch*.csv | Sort-Object Name
    $ActualBatchCount = $AllBatchFiles.Count

    Write-Log -Message "Created $ActualBatchCount batch files."    -Level INFO -LogPath $MainLogPath

    $TotalRounds = [math]::Ceiling($ActualBatchCount / $Number)

    Write-Log -Message "Concurrent sessions : $Number"      -Level INFO -LogPath $MainLogPath
    Write-Log -Message "Total rounds needed : $TotalRounds" -Level INFO -LogPath $MainLogPath

    # Pre-build module/dot-source commands once
    $ImportModuleCommands = Get-ImportModuleCommands -Modules $ImportModule
    $DotSourceCommands    = Get-DotSourceCommands    -Scripts $DotSourceScript

    # Pre-convert script blocks to string BEFORE entering here-strings
    $SetupBlockText = $SetupBlock.ToString()
    $ItemBlockText  = $ItemBlock.ToString()

    # =========================================================================
    # PROCESS ROUNDS
    # =========================================================================
    for ($round = 0; $round -lt $TotalRounds; $round++) {
        $currentRound = $round + 1

        $startBatch       = $round * $Number
        $endBatch         = [math]::Min($startBatch + $Number - 1, $ActualBatchCount - 1)
        $batchesThisRound = $AllBatchFiles[$startBatch..$endBatch]

        Write-Log -Message "=== ROUND $currentRound of $TotalRounds ===" -Level INFO -LogPath $MainLogPath
        Write-Log -Message "Processing batches $($startBatch + 1) to $($endBatch + 1) ($($batchesThisRound.Count) concurrent sessions)" -Level INFO -LogPath $MainLogPath

        $RunningSessions = @()
        $TempScripts     = @()

        # ------------------------------------------------------------------
        # Step 2: Launch one PowerShell session per batch in this round
        # ------------------------------------------------------------------
        foreach ($SingleBatch in $batchesThisRound) {
            $BatchNumber = ($SingleBatch.BaseName -replace '\D', '')

            $BatchLogFile      = Join-Path $LogFolder "$ComputerPrefix-Log-Batch$BatchNumber.txt"
            $BatchProgressFile = Join-Path $LogFolder "$ComputerPrefix-Progress-Batch$BatchNumber.txt"
            $BatchDoneFlag     = Join-Path $LogFolder "$ComputerPrefix-Done-Batch$BatchNumber.flag"

            # Clean up leftover flag from a previous run
            if (Test-Path $BatchDoneFlag) { Remove-Item $BatchDoneFlag -Force }

            $TempScript  = [System.IO.Path]::GetTempFileName().Replace('.tmp', '.ps1')
            $TempScripts += $TempScript

            $ScriptContent = @"
param ([int]`$Batch)

Start-Transcript -Path "$BatchLogFile" -Append -Force | Out-Null

try {
    `$BatchNumber       = $BatchNumber
    `$CurrentPath       = "$CurrentPath"
    `$LogFile           = "$BatchLogFile"
    `$ProgressFile      = "$BatchProgressFile"
    `$ReconnectInterval = $ReconnectInterval

    Write-Host "========================================"
    Write-Host "Batch `$BatchNumber started : `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "Server        : $ComputerPrefix"
    Write-Host "Log file      : `$LogFile"
    Write-Host "Progress file : `$ProgressFile"
    Write-Host "Input CSV     : $($SingleBatch.FullName)"
    Write-Host "========================================"

    # -----------------------------------------------------------------
    # Import modules / dot-source (from -ImportModule and -DotSourceScript params)
    # -----------------------------------------------------------------
    $ImportModuleCommands
    $DotSourceCommands

    # -----------------------------------------------------------------
    # Load the batch list
    # -----------------------------------------------------------------
    `$Script:List = Import-Csv -Path "$($SingleBatch.FullName)"
    Write-Host "Loaded `$(`$Script:List.Count) items from CSV."

    # -----------------------------------------------------------------
    # Run SetupBlock once before the loop
    # -----------------------------------------------------------------
    Write-Host "--- Running SetupBlock ---"
    $SetupBlockText
    Write-Host "--- SetupBlock complete ---"

    # -----------------------------------------------------------------
    # Initialise results collection — ItemBlock adds to this via `$Script:Results.Add()
    # -----------------------------------------------------------------
    `$Script:Results = [System.Collections.Generic.List[object]]::new()

    # -----------------------------------------------------------------
    # Wrapper-owned loop
    # -----------------------------------------------------------------
    `$i             = 0
    `$Total         = `$Script:List.Count
    `$CurrentObject = ""

    foreach (`$item in `$Script:List) {
        `$i++

        # Reconnect every N items by re-running SetupBlock
        if (`$ReconnectInterval -gt 0 -and `$i % `$ReconnectInterval -eq 0) {
            Write-Host "[`$i/`$Total] Reconnecting (interval: `$ReconnectInterval)..."
            $SetupBlockText
            Write-Host "[`$i/`$Total] Reconnect complete."
        }

        # Progress file write — retry up to 20x every 2s (file lock safe)
        `$WriteAttempt = 0
        `$WriteSuccess = `$false
        while (-not `$WriteSuccess -and `$WriteAttempt -lt 20) {
            try {
                @"
Server=$ComputerPrefix
Current=`$i
Total=`$Total
CurrentObject=`$CurrentObject
"@ | Set-Content -Path "`$ProgressFile" -Encoding UTF8
                `$WriteSuccess = `$true
            }
            catch {
                `$WriteAttempt++
                Start-Sleep -Seconds 2
            }
        }
        if (-not `$WriteSuccess) {
            Write-Host "[`$i/`$Total] WARN — Could not write progress file after 20 attempts. Continuing..."
        }

        # Reset CurrentObject — ItemBlock sets this at the top of its logic
        `$CurrentObject = ""

        # ---- RUN ITEM BLOCK ----
        $ItemBlockText
        # ---- END ITEM BLOCK ----
    }

    Write-Host "========================================"
    Write-Host "Batch `$BatchNumber loop complete : `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "Total results collected : `$(`$Script:Results.Count)"
    Write-Host "========================================"

    # -----------------------------------------------------------------
    # Export output — wrapper owns this, do not put Export-Csv in ItemBlock
    # -----------------------------------------------------------------
    `$Script:Results | Export-Csv -Path ".\Batches\Output-Batch`$BatchNumber.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "Output exported to .\Batches\Output-Batch`$BatchNumber.csv"
}
catch {
    Write-Host "[ERROR] Batch $BatchNumber failed: `$(`$_.Exception.Message)"
    Write-Host `$_.ScriptStackTrace
    Stop-Transcript | Out-Null
    exit 1
}

Stop-Transcript | Out-Null

# Write done flag as the VERY LAST action — signals clean completion to main session
Set-Content -Path "$BatchDoneFlag" -Value "DONE: `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8
"@

            Set-Content -Path $TempScript -Value $ScriptContent -Encoding UTF8

            Write-Log -Message "Starting Batch $BatchNumber (log: $BatchLogFile)" -Level INFO -LogPath $MainLogPath

            $Process = Start-Process powershell.exe `
                -ArgumentList "-ExecutionPolicy Bypass", "-File `"$TempScript`"", "-Batch $BatchNumber" `
                -PassThru

            $RunningSessions += @{
                BatchNumber  = $BatchNumber
                Process      = $Process
                DoneFlag     = $BatchDoneFlag
                ProgressFile = $BatchProgressFile
                LogFile      = $BatchLogFile
                StartTime    = Get-Date
                Status       = "Running"
            }

            Write-Log -Message "Batch $BatchNumber launched (PID: $($Process.Id))" -Level INFO -LogPath $MainLogPath
        }

        # ------------------------------------------------------------------
        # Step 3: Monitor loop — check every 10 seconds
        # ------------------------------------------------------------------
        Write-Log -Message "Monitoring Round $currentRound ($($RunningSessions.Count) sessions)..." -Level INFO -LogPath $MainLogPath

        $TimeoutSeconds = $TimeoutMinutes * 60
        $AbortRound     = $false

        Do {
            Start-Sleep -Seconds 10

            $stillRunning = @()

            foreach ($session in $RunningSessions) {
                if ($session.Status -ne "Running") { continue }

                $batchNum = $session.BatchNumber
                $proc     = $session.Process
                $elapsed  = (Get-Date) - $session.StartTime
                $doneFlag = $session.DoneFlag
                $progFile = $session.ProgressFile

                # Check 1: Done flag = clean completion
                if (Test-Path $doneFlag) {
                    $session.Status = "Done"
                    Write-Log -Message "Batch $batchNum COMPLETED successfully (elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) min)" -Level SUCCESS -LogPath $MainLogPath
                    continue
                }

                # Check 2: Process exited but no done flag = crashed
                if ($proc.HasExited) {
                    $session.Status = "Failed"
                    Write-Log -Message "Batch $batchNum CRASHED (exit code: $($proc.ExitCode)) — no done flag found." -Level ERROR -LogPath $MainLogPath
                    Write-Log -Message "See log: $($session.LogFile)" -Level ERROR -LogPath $MainLogPath
                    $AbortRound = $true
                    break
                }

                # Check 3: Timeout exceeded
                if ($elapsed.TotalSeconds -gt $TimeoutSeconds) {
                    $session.Status = "TimedOut"
                    Write-Log -Message "Batch $batchNum TIMED OUT after $TimeoutMinutes minutes. Killing PID $($proc.Id)." -Level ERROR -LogPath $MainLogPath
                    try { $proc.Kill() } catch { }
                    $AbortRound = $true
                    break
                }

                # Still running — show progress
                $progress = Read-ProgressFile -Path $progFile

                if ($progress -and $progress.Total -gt 0) {
                    $pct = [math]::Round(($progress.Current / $progress.Total) * 100, 1)
                    $eta = Format-ETA -Current $progress.Current -Total $progress.Total -Elapsed $elapsed
                    Write-Log -Message "Batch $batchNum | $($progress.Current)/$($progress.Total) ($pct%) | Object: $($progress.CurrentObject) | Remaining: $eta" -Level INFO -LogPath $MainLogPath
                }
                else {
                    Write-Log -Message "Batch $batchNum | Running... (elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) min) — no progress data yet" -Level INFO -LogPath $MainLogPath
                }

                $stillRunning += $session
            }

            # Abort — kill all remaining sessions
            if ($AbortRound) {
                Write-Log -Message "ABORTING Round $currentRound — killing all remaining sessions." -Level ERROR -LogPath $MainLogPath

                foreach ($session in $RunningSessions) {
                    if ($session.Status -eq "Running") {
                        try {
                            $session.Process.Kill()
                            Write-Log -Message "Killed Batch $($session.BatchNumber) (PID: $($session.Process.Id))" -Level WARN -LogPath $MainLogPath
                        }
                        catch { }
                        $session.Status = "Killed"
                    }
                }
                break
            }

        } until ($stillRunning.Count -eq 0)

        # ------------------------------------------------------------------
        # Step 4: Cleanup temp scripts
        # ------------------------------------------------------------------
        foreach ($ts in $TempScripts) {
            if (Test-Path $ts) { Remove-Item $ts -Force -ErrorAction SilentlyContinue }
        }

        # ------------------------------------------------------------------
        # Step 5: Abort if any batch failed — do not continue to next round
        # ------------------------------------------------------------------
        if ($AbortRound) {
            $failedBatches = $RunningSessions | Where-Object { $_.Status -in @("Failed", "TimedOut") } | ForEach-Object { "Batch$($_.BatchNumber)" }
            Write-Log -Message "Run ABORTED. Failed/timed-out: $($failedBatches -join ', ')" -Level ERROR -LogPath $MainLogPath
            Write-Log -Message "Report is incomplete. Check individual batch logs in: $LogFolder" -Level ERROR -LogPath $MainLogPath
            return
        }

        Write-Log -Message "Round $currentRound COMPLETED successfully." -Level SUCCESS -LogPath $MainLogPath
    }

    Write-Log -Message "ALL $TotalRounds ROUNDS COMPLETED. Total batches processed: $ActualBatchCount" -Level SUCCESS -LogPath $MainLogPath
}
