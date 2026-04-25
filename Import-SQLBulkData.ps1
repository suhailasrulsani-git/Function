function Import-SQLBulkData {
    <#
    .SYNOPSIS
        Bulk imports a CSV file into a SQL Server table using SqlBulkCopy.

    .DESCRIPTION
        Reads a CSV file and bulk inserts its contents into a target SQL Server table.
        The target table is truncated before insert. Both operations are wrapped in a
        transaction — if the insert fails, the truncate is rolled back automatically.

        Assumes the CSV header row matches the target table column names exactly.

    .PARAMETER FilePath
        Path to the .csv file to import.

    .PARAMETER Server
        SQL Server name and instance. Format: SERVER\INSTANCE

    .PARAMETER Database
        Target database name.

    .PARAMETER Table
        Target table name.

    .PARAMETER Username
        SQL Server login username.

    .PARAMETER Password
        SQL Server login password (plain text).
        WARNING: Avoid passing this directly on the command line — it will appear in
        your session history. Consider reading it from a secrets store or prompting
        at runtime using: -Password (Read-Host "Password")

    .PARAMETER BatchSize
        Number of rows sent per batch to SQL Server. Default is 1000.
        Increase for faster imports on large files; decrease if you hit memory limits.

    .EXAMPLE
        Import-SQLBulkData -FilePath .\file.csv -Server "SQLSERVER\INSTANCE" `
            -Database "EUSAutomation" -Table "tbl_test" `
            -Username "testusername" -Password "testpassword"

    .EXAMPLE
        # Safer password handling — prompts at runtime, not stored in history
        Import-SQLBulkData -FilePath .\file.csv -Server "SQLSERVER\INSTANCE" `
            -Database "EUSAutomation" -Table "tbl_test" `
            -Username "testusername" -Password (Read-Host "Enter password")
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory)]
        [string]$Table,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$BatchSize = 1000
    )

    # -------------------------------------------------------------------------
    # 1. Validate file extension
    # -------------------------------------------------------------------------
    if ([System.IO.Path]::GetExtension($FilePath) -ne '.csv') {
        Write-Error "FilePath must point to a .csv file. Got: $FilePath"
        return
    }

    # -------------------------------------------------------------------------
    # 2. Read CSV
    # -------------------------------------------------------------------------
    Write-Verbose "Reading CSV from: $FilePath"
    try {
        $csvData = Import-Csv -Path $FilePath
    }
    catch {
        Write-Error "Failed to read CSV file: $_"
        return
    }

    if ($csvData.Count -eq 0) {
        Write-Warning "CSV file is empty. Nothing to import."
        return
    }

    Write-Verbose "Rows read from CSV: $($csvData.Count)"

    # -------------------------------------------------------------------------
    # 3. Build DataTable from CSV (SqlBulkCopy requires a DataTable or IDataReader)
    # -------------------------------------------------------------------------
    $dataTable = New-Object System.Data.DataTable

    # Add columns based on CSV headers
    $csvData[0].PSObject.Properties.Name | ForEach-Object {
        [void]$dataTable.Columns.Add($_)
    }

    # Populate rows
    foreach ($row in $csvData) {
        $dataRow = $dataTable.NewRow()
        foreach ($col in $dataTable.Columns) {
            $dataRow[$col.ColumnName] = $row.$($col.ColumnName)
        }
        $dataTable.Rows.Add($dataRow)
    }

    Write-Verbose "DataTable built with $($dataTable.Rows.Count) rows and $($dataTable.Columns.Count) columns."

    # -------------------------------------------------------------------------
    # 4. Connect to SQL Server
    # -------------------------------------------------------------------------
    $connectionString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True;"

    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)

    try {
        Write-Verbose "Opening connection to $Server\$Database..."
        $connection.Open()
    }
    catch {
        Write-Error "Failed to connect to SQL Server: $_"
        return
    }

    # -------------------------------------------------------------------------
    # 5. Begin transaction — wraps TRUNCATE + INSERT
    #    If bulk insert fails, truncate is rolled back automatically.
    # -------------------------------------------------------------------------
    $transaction = $connection.BeginTransaction()

    try {
        # --- Truncate table ---
        Write-Verbose "Truncating table: $Table"
        $truncateCmd = $connection.CreateCommand()
        $truncateCmd.Transaction = $transaction
        $truncateCmd.CommandText = "TRUNCATE TABLE [$Table]"
        [void]$truncateCmd.ExecuteNonQuery()

        # --- Bulk insert ---
        Write-Verbose "Starting bulk insert with batch size: $BatchSize"
        $bulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy(
            $connection,
            [System.Data.SqlClient.SqlBulkCopyOptions]::TableLock,
            $transaction
        )
        $bulkCopy.DestinationTableName = "[$Table]"
        $bulkCopy.BatchSize            = $BatchSize
        $bulkCopy.BulkCopyTimeout      = 300  # seconds; increase for very large files

        # Map each CSV column to the matching table column by name
        foreach ($col in $dataTable.Columns) {
            [void]$bulkCopy.ColumnMappings.Add($col.ColumnName, $col.ColumnName)
        }

        $bulkCopy.WriteToServer($dataTable)
        $bulkCopy.Close()

        # --- Commit ---
        $transaction.Commit()

        Write-Host "SUCCESS: $($dataTable.Rows.Count) rows imported into [$Database].[$Table]." -ForegroundColor Green
    }
    catch {
        # Rollback on any failure — table is left untouched
        Write-Warning "Import failed. Rolling back transaction — table data is unchanged."
        try { $transaction.Rollback() } catch { Write-Warning "Rollback also failed: $_" }
        Write-Error "Bulk import error: $_"
    }
    finally {
        $connection.Close()
        Write-Verbose "Connection closed."
    }
}
