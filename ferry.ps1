

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
    
    $orderData = ExecuteScalarXml $settings.ordersDatabase.server $settings.ordersDatabase.database "dbo.GPO_orderXML_download"
    $filename = CreateTemporaryFile
    $orderData | Out-File $filename

    # Clean up
    Remove-Item $filename

    Write-Host $orderData
    Write-Host $filename
}


<#
    Method for reading a single XML blob returned from a FOR XML query (or one embedded in a stored proc.)
    Use this instead of ExecuteScalar as ExecuteScalar will truncate XML at 2,033 characters.
    See: https://support.microsoft.com/en-us/help/310378/

    TODO: Replace server, database, etc. with a connection string.

    @param $server - the database server to connect to.
    @param $database - the database instance
    @param $query - the query (or stored procedure) to execute
#>
function ExecuteScalarXml( $server, $database, $query ) {

    $connectionString = "Data Source=$server;" +
        "Integrated Security=true; " +
        "Initial Catalog=$database"
    Write-Host "connection string:" $connectionString

    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $command = new-object system.data.sqlclient.sqlcommand($query,$connection)
    $connection.Open()

    # Powershell 2 doesn't have a using statement, so we do it by hand.
    $xmlBlob = ''
    $xmlReader = $command.ExecuteXmlReader();
    try {
        while( $xmlReader.Read() ) {
            $xmlBlob = $xmlReader.ReadOuterXml()
        }
    }
    finally {
        $xmlReader.Close()
        $connection.Close()
    }

    return $xmlBlob
}


<#
    TODO: Replace server, database, etc. with a connection string.

    @param $server - the database server to connect to.
    @param $database - the database instance
    @param $query - the query (or stored procedure) to execute
#>
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


function CreateTemporaryFile() {
    $path = [System.IO.Path]::GetTempPath()
    $filename = [System.Guid]::NewGuid().ToString() + ".xml"
    return [System.IO.Path]::Combine( $path,  $filename )
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
    <ftp server="" userid="" password="" />
</settings>
"@

    return $settings.settings
}

Main