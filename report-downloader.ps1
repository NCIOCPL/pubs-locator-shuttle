<#
    Retrieves reports from the Government Printing Office FTP server and stores them
    in the pubs locator database for processing.
#>

# Data structure for managing the set of reports to be retrieved.
$reports = [xml]@"
    <reports>
        <report name="Inventory"    remoteFilename="" localFilename="" storageProcedure="" />
        <report name="Fullfillment" remoteFilename="" localFilename="" storageProcedure="" />
    </reports>
"@


function Main() {
    try {

        $settings = GetSettings

        # Contains an enumerable collection of report data structures.  This is more useful
        # than the underlaying XML document structure.
        $reportList = $reports.reports.report

        # Download the rpeorts
        DownloadReports $reportList $settings.ftp.server $settings.ftp.userid $settings.ftp.password

        # Save reports to database.
        SaveReports $reportList $settings.ordersDatabase


        #$exportFilename = GetExportFileName $settings.testmode
        #$orderData | Out-File $exportFilename

        # Clean up
        #Remove-Item $exportFilename
    }
    catch [System.Exception] {
        ReportError  "Downloading reports" $_ $settings
    }
}

<#
    Connects to the GPO SFTP server and downloads the reports identified by $reportList.

    The reportList structure is updated to include the indvidual report's filenames and paths
    on the local file system.
#>
function DownloadReports( $reportList, $server, $userid, $password ) {
    $server = $server
    $userid = $userid
    $password = $password

    # TODO: Determine remote file names.
    # TODO: Download the individual files.
    # TODO: Determine local file names.
    $reportList | ForEach-Object {
        Write-Host "Download:" $_.name

        # This is (probably) only temporary
        $_.localFilename = $_.name + ".xml"
    }

    #cmd /c echo put $exportFilename | psftp $userid@$server -pw $password -batch -bc
}


<#
    Loads report files identified in the localFilename element of each entry in $reportList
    and saves it in the database.
#>
function SaveReports($reportList, $databaseInfo) {

    $reportList | ForEach-Object { Write-Host $_.localFilename }

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
function ReportError( $stage, $ex, $settings ) {

    $message = $ex.ToString()
    $explanationMessage = "Error occured in the '$stage' stage.`n$ex`nError at line: " +
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