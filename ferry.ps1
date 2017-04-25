

function Main() {
    try {
        $settings = GetSettings
        SendOrders $settings
    }
    catch {
        ReportError $_
    }
}

function SendOrders( $settings ) {
    Write-Host "Doing some stuff"
    
    $table = ExecuteDataTable $settings.ordersDatabase.server $settings.ordersDatabase.database "dbo.GPO_orderXML_download"

    Write-Host $table.GetType().Name

    Write-Host "Column Count: " $table.Columns[0].ColumnName

    $table | foreach {
        Write-Host $_.GetType().Name
        Write-Host "row " $_[0].length
    }
}


function ExecuteDataTable( $server, $database, $query ) {
    Write-Host "  server: " $server
    Write-Host "database: " $database
    Write-Host "   query: " $query

    $connectionString = "Data Source=$server;" +
        "Integrated Security=true; " +
        "Initial Catalog=$database"
    Write-Host "connection string:" $connectionString

    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $command = new-object system.data.sqlclient.sqlcommand($query,$connection)
    $connection.Open()

    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
    $dataTable = New-Object System.Data.DataTable
    $adapter.Fill($dataTable) | Out-Null

    $connection.Close()

    # Powershell wants to unwind System.Data.DataTable into an array of DataRow objects.
    # By using the comma operator, we create an array which causes the DataTable to be returned
    # to the caller, with all its built-in properties intact.
    return ,$dataTable
}


function ReportError( $ex ) {
    Write-Host -foregroundcolor 'red' "I fall down and go boom!"
    Write-Host -foregroundcolor 'red' $ex
    Write-Host -foregroundcolor 'red' "Real error handling goes here"
}

function GetSettings() {

    $settings = [xml]@"
<settings>
    <ordersDatabase server="SERVER\INSTANCE,PORT" database="DATABASE" />
</settings>
"@

    return $settings.settings
}

Main