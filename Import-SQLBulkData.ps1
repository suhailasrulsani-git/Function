function Import-SQLBulkData {
    <#
    .SYNOPSIS
        Bulk imports a CSV file into a SQL Server table using SqlBulkCopy.

    .DESCRIPTION
        Reads a CSV file and bulk inserts its contents into a target SQL Server table.
        The target table is truncated before insert. Both operations are wrapped in a
        transaction — if the insert fails, the truncate is rolled back automatically.

        Column types are resolved dynamically from the target table's schema in SQL Server.
        Rows that fail type casting are silently skipped.

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
    # INTERNAL: Maps SQL Server data types to .NET types for DataTable columns
    # -------------------------------------------------------------------------
    function Get-DotNetType {
        param ([string]$SqlType)

        switch ($SqlType.ToLower()) {
            'int'            { return [int] }
            'bigint'         { return [long] }
            'smallint'       { return [int16] }
            'tinyint'        { return [byte] }
            'decimal'        { return [decimal] }
            'numeric'        { return [decimal] }
            'float'          { return [double] }
            'real'           { return [single] }
            'bit'            { return [bool] }
            'datetime'       { return [datetime] }
            'datetime2'      { return [datetime] }
            'date'           { return [datetime] }
            'smalldatetime'  { return [datetime] }
            'varchar'        { return [string] }
            'nvarchar'       { return [string] }
            'char'           { return [string] }
            'nchar'          { return [string] }
            'text'           { return [string] }
            'ntext'          { return [string] }
            'uniqueidentifier'{ return [string] }
            default          { return [string] }
        }
    }

    # -------------------------------------------------------------------------
    # INTERNAL: Attempts to cast a string value to the target .NET type.
    # Returns $null and sets $ok to $false on failure.
    # -------------------------------------------------------------------------
    function Convert-Value {
        param (
            [string]$Value,
            [type]$TargetType,
            [ref]$Ok
        )

        $Ok.Value = $true

        # Pass strings through unchanged
        if ($TargetType -eq [string]) {
            return $Value
        }

        # Treat empty or whitespace-only as DBNull
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return [System.DBNull]::Value
        }

        try {
            return [System.Convert]::ChangeType($Value, $TargetType)
        }
        catch {
            $Ok.Value = $false
            return $null
        }
    }

    # =========================================================================
    # 1. Validate file extension
    # =========================================================================
    if ([System.IO.Path]::GetExtension($FilePath) -ne '.csv') {
        Write-Error "FilePath must point to a .csv file. Got: $FilePath"
        return
    }

    # =========================================================================
    # 2. Read CSV
    # =========================================================================
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

    # =========================================================================
    # 3. Connect to SQL Server (needed for schema query)
    # =========================================================================
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

    # =========================================================================
    # 4. Query target table schema from SQL Server
    #    Builds a hashtable: ColumnName -> .NET Type
    # =========================================================================
    Write-Verbose "Querying schema for table: $Table"
    $schemaMap = @{}

    try {
        $schemaQuery = @"
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '$Table'
  AND TABLE_CATALOG = '$Database'
ORDER BY ORDINAL_POSITION
"@
        $schemaCmd = $connection.CreateCommand()
        $schemaCmd.CommandText = $schemaQuery
        $reader = $schemaCmd.ExecuteReader()

        while ($reader.Read()) {
            $colName  = $reader["COLUMN_NAME"]
            $sqlType  = $reader["DATA_TYPE"]
            $schemaMap[$colName] = Get-DotNetType -SqlType $sqlType
        }
        $reader.Close()
    }
    catch {
        Write-Error "Failed to retrieve table schema: $_"
        $connection.Close()
        return
    }

    if ($schemaMap.Count -eq 0) {
        Write-Error "No columns found for table '$Table' in database '$Database'. Check table name and permissions."
        $connection.Close()
        return
    }

    Write-Verbose "Schema loaded: $($schemaMap.Count) columns resolved."

    # =========================================================================
    # 5. Build DataTable using schema-driven column types
    # =========================================================================
    $dataTable = New-Object System.Data.DataTable

    # Only add columns that exist in both the CSV and the schema
    $csvColumns = $csvData[0].PSObject.Properties.Name
    $mappedColumns = @()

    foreach ($col in $csvColumns) {
        if ($schemaMap.ContainsKey($col)) {
            [void]$dataTable.Columns.Add($col, $schemaMap[$col])
            $mappedColumns += $col
        }
        else {
            Write-Verbose "CSV column '$col' not found in table schema — skipping column."
        }
    }

    # =========================================================================
    # 6. Populate DataTable rows — silently skip rows with cast failures
    # =========================================================================
    $skippedRows = 0

    foreach ($row in $csvData) {
        $dataRow  = $dataTable.NewRow()
        $rowValid = $true

        foreach ($col in $mappedColumns) {
            $rawValue  = $row.$col
            $targetType = $schemaMap[$col]
            $castOk    = $true

            $converted = Convert-Value -Value $rawValue -TargetType $targetType -Ok ([ref]$castOk)

            if (-not $castOk) {
                $rowValid = $false
                break
            }

            $dataRow[$col] = $converted
        }

        if ($rowValid) {
            $dataTable.Rows.Add($dataRow)
        }
        else {
            $skippedRows++
        }
    }

    Write-Verbose "Rows queued for insert : $($dataTable.Rows.Count)"
    Write-Verbose "Rows silently skipped  : $skippedRows"

    if ($dataTable.Rows.Count -eq 0) {
        Write-Warning "No valid rows to import after type validation. Table was not modified."
        $connection.Close()
        return
    }

    # =========================================================================
    # 7. Begin transaction — wraps TRUNCATE + INSERT
    #    If bulk insert fails, truncate is rolled back automatically.
    # =========================================================================
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
        $bulkCopy.BulkCopyTimeout      = 300

        foreach ($col in $mappedColumns) {
            [void]$bulkCopy.ColumnMappings.Add($col, $col)
        }

        $bulkCopy.WriteToServer($dataTable)
        $bulkCopy.Close()

        # --- Commit ---
        $transaction.Commit()

        Write-Host "SUCCESS: $($dataTable.Rows.Count) rows imported into [$Database].[$Table]." -ForegroundColor Green
    }
    catch {
        Write-Warning "Import failed. Rolling back transaction — table data is unchanged."
        try { $transaction.Rollback() } catch { Write-Warning "Rollback also failed: $_" }
        Write-Error "Bulk import error: $_"
    }
    finally {
        $connection.Close()
        Write-Verbose "Connection closed."
    }
}
