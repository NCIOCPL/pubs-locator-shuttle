<#
    Retrieves reports from the Government Printing Office FTP server and stores them
    in the pubs locator database for processing.
#>

# Data structure for managing the set of reports to be retrieved.
$reports = [xml]@"
    <reports>
        <report name="Inventory"   remoteFilename="InventoryReport"   storageProcedure="GPO_inventory_import" />
        <report name="Fulfillment" remoteFilename="FulfillmentReport" storageProcedure="GPO_shipping_import" />
    </reports>
"@


function Main() {
    $settings = GetSettings

    # Contains an enumerable collection of report data structures.  This is more useful
    # than the underlaying XML document structure.
    $reportList = $reports.reports.report

    $reportList | ForEach-Object {

        $report = $_
        try {
            # Get the report
            Write-Host -foregroundcolor 'green' "Downloading" $_.name "report"
            $data = GetReportData $_.remoteFilename $settings.ftp.server $settings.ftp.userid $settings.ftp.password $settings.ftp.downloadPath

            # Save reports to database.
            Write-Host -foregroundcolor 'green' "Saving report" $_.name
            SaveReports $data $settings.ordersDatabase.connectionString $_.storageProcedure
        }
        catch {
            $message = "Unable to retrieve report" + $report.name
            ReportError $message $_ $settings
        }
    }
}

<#
    Connects to the GPO SFTP server and downloads the reports identified by $reportList.

    The reportList structure is updated to include the indvidual report's filenames and paths
    on the local file system.
#>
function GetReportData( $reportName, $server, $userid, $password, $downloadPath ) {
    $server = $server
    $userid = $userid
    $password = $password

    # Remote file names are the report name, with the date appended in the format yyyyMMdd
    $remoteName = GetRemoteFilename $downloadPath $reportName

    # Download to a temporary location.
    $localFilename = [system.io.path]::GetTempFileName()

    # Download the individual file.
    # Becasuse psftp writes to standard out, it must be piped to Out-Null in order to prevent it being captured in the return data stream,
    cmd /c echo get $remoteName $localFilename | psftp $userid@$server -pw $password -batch -bc | Out-Null

    try {
        $loadedData = LoadDataFile $localFilename
    }
    catch {
        throw "Unable to load $remoteName"
    }

    # Cleanup
    Remove-Item $localFilename

    return $loadedData
}

<#
    Computes the expected name of a report data file on the remote system by
    appending the current date in a yyyyMMdd format.

    @downloadPath - The path where the file is expected to be found.
    @reportName - The report's root file name.
#>
function GetRemoteFilename( $downloadPath, $reportName ) {
    $datePart = [System.DateTime]::Now.ToString("yyyyMMdd")
    $filename = "$reportName-$datePart.xml"

    # Make sure the download path has all the expected separators
    if ( -not $downloadPath ) { $downloadPath = '/' }
    if ( -not $downloadPath.StartsWith('/')) { $downloadPath = '/' + $downloadPath }
    if ( -not $downloadPath.EndsWith('/')) { $downloadPath = $downloadPath + '/' }

    # Combine name and path
    $remoteName = $downloadPath + $filename

    return $remoteName
}


<#
    Loads report files identified in the localFilename element of each entry in $reportList
    and saves it in the database.

    @reportXML - XML document containing the report
    @connectionString - SQL Server connection string.
    @procedureName - The name of the stored procedure to use for saving the report

#>
function SaveReports($reportXML, $connectionString, $procedureName) {

    $xmlParam = new-object system.data.SqlClient.SqlParameter( "@xml", [system.data.SqlDbType]::Text )
    $xmlParam.value = $reportXML
    $paramList = ,$xmlParam

    # ExecuteNonQuery returns  the number of rows affected, or -1 if a rollback event occurs.
    # Assumptions:
    #   Rollbacks will only happen when an error occurs.
    #   Stored procs will *NOT* set "nocount on" as this also causes the row count to be -1.
    $rowCount = ExecuteNonQuery $connectionString $procedureName "StoredProcedure" $paramList
    if( $rowCount -lt 0 ) {
        throw "An error occured while executing '$procedureName'."
    }
}

<#
    Execute a SQL Query which doesn't return anything.

    @connectionString - ADO.Net connection string for connecting to the database server.
            e.g. A connectionString value using Windows authention might look something like
            "Data Source=MY_SERVER\INSTANCE,PORT; Initial Catalog=MY_DATABASE; Integrated Security=true;"

    @commandText - The SQL Command to execute.

    @commandType - String containing the name of the type of SQL Command being executed.
                   May be any supported value of System.Data.CommandType

    @paramList - Iterable collection of SQLParameter objects.
#>
function ExecuteNonQuery( $connectionString, $commandText, $commandType, $paramList ) {

    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $command = new-object system.data.sqlclient.sqlcommand("[$commandText]", $connection)
    $command.CommandType = $commandType

    # Attach the paramters to the command object.
    $paramList | ForEach-Object {
        $command.Parameters.Add( $_ ) | Out-Null
    }

    $connection.Open()
    # Powershell 2 doesn't have a using statement, so we do it by hand.
    try {
        $rowsAffected = $command.ExecuteNonQuery()
    }
    finally {
        $connection.Close()
    }

    return $rowsAffected
}


<#
    Returns the content of the named text file

    $filename - Name and path of a text file to retrieve.
#>
function LoadDataFile( $filename ) {

    $data = Get-Content $filename

    # Get-Content returns an array of strings.  We need to convert them to one big string with no-delimiters
    return [String]::Join('', $data)
}


<#
    Creates a timestamp-based filename with a fully-resolved path to the user's
    temporary path.  For exact location rules, see the remarks in
    https://msdn.microsoft.com/en-us/library/system.io.path.gettemppath(v=vs.110).aspx

    @param $testFile - If set to any value other than '0' or NULL, the filename will be prepended with the string "TEST-"
#>
function GetExportFileName( $testFile ) {

    if( -not $testFile -or ($testFile -eq '0') -or ($testFile -eq 0)) {
        $formatter = "yyyyMMdd-HHmmss"
    } else {
        $formatter = "NCI-TEST-yyyyMMdd-HHmmss"
    }

    $path = [System.IO.Path]::GetTempPath()
    $filename = [System.DateTime]::Now.ToString($formatter) + ".xml"
    return [System.IO.Path]::Combine( $path,  $filename )
}


<#
    Report errors in the import/export processing flow.

    @param $stage - String containing the name of the processing stage that failed.
    @param $ex - An ErrorRecord object containing details of the error which failed.
#>
function ReportError( $message, $ex, $settings ) {

    $explanationMessage = "$message.`n$ex`n`n`nError at line: " +
            $ex.InvocationInfo.ScriptLineNumber + "`n" +
            $ex.InvocationInfo.line

    Write-Host -foregroundcolor 'red' $explanationMessage

    if( $settings.errorReporting -and $settings.email) {
        send-mailmessage `
            -SmtpServer $settings.email.server `
            -From $settings.errorReporting.from `
            -To $settings.errorReporting.to `
            -Subject $settings.errorReporting.subjectLine `
            -BODY $explanationMessage
    }
}

function GetSettings() {

    [xml]$settings = Get-Content "settings.xml"

    return $settings.settings
}

Main