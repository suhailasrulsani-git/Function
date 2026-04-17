function Invoke-SqlQuery {
    param (
        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter(Mandatory)]
        [string]$Database,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password,

        [Parameter(Mandatory)]
        [string]$Query
    )

    $connectionString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;"

    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        $command = $connection.CreateCommand()
        $command.CommandText = $Query

        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset) | Out-Null

        $results = $dataset.Tables[0].Rows | ForEach-Object {
            [PSCustomObject]$_
        }

        return $results
    }
    catch {
        Write-Error "Database error: $_"
    }
    finally {
        $connection.Close()
    }
}
