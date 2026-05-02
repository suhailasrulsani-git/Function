# ==============================================================================
# TEMPLATE: Start-Parallel
# ==============================================================================

cd "E:\Scripts\Temp\SCRIPTFOLDER"
. .\module.ps1

$MainListPath = Get-ChildItem -Path .\ -Filter *.csv

Start-Parallel `
    -Number             4 `
    -MainListPath       "$($MainListPath.FullName)" `
    -OutputFolder       ".\Batches" `
    -LogFolder          "\\FILESERVER\SHAREPATH\logs" `
    -TimeoutMinutes     60 `
    -ReconnectInterval  1000 `
    -SetupBlock {
        # ------------------------------------------------------------------
        # Runs ONCE before the loop — and again every -ReconnectInterval items
        # Put: module loads, dot-sources, Exchange Online connect
        # ------------------------------------------------------------------
        . .\module.ps1
        . .\reconnect_online.ps1
    } `
    -ItemBlock {
        # ------------------------------------------------------------------
        # Runs ONCE PER ITEM — wrapper calls this inside the foreach loop
        #
        # Available variables injected by wrapper:
        #   $item    — current CSV row         e.g. $item.PrimarySmtpAddress
        #   $i       — current index            e.g. 42
        #   $Total   — total items in batch     e.g. 500
        #
        # You MUST set $CurrentObject — wrapper uses it for the progress file
        #   $CurrentObject = $item.COLUMNNAME
        #
        # Add results via:
        #   $Script:Results.Add([PSCustomObject]@{ ... })
        #
        # Do NOT put: foreach loop, Export-Csv, progress file write, reconnect logic
        # ------------------------------------------------------------------

        $CurrentObject = $item.COLUMNNAME   # <-- required: shown in progress log

        try {

            # YOUR LOGIC HERE
            # e.g. $Stats = Get-EXOMailboxStatistics -Identity $item.Guid -ErrorAction Stop

            $Script:Results.Add([PSCustomObject]@{
                Column1      = $item.COLUMNNAME
                Column2      = "VALUE"
                LastUpdated  = Get-Date
                ScriptServer = $env:COMPUTERNAME
            })

            Write-Host "[$i/$Total] OK — $($item.COLUMNNAME)"
        }
        catch {
            Write-Host "[$i/$Total] ERROR — $($item.COLUMNNAME) : $($_.Exception.Message)"

            $Script:Results.Add([PSCustomObject]@{
                Column1      = $item.COLUMNNAME
                Column2      = "ERROR: $($_.Exception.Message)"
                LastUpdated  = Get-Date
                ScriptServer = $env:COMPUTERNAME
            })
        }
    }
