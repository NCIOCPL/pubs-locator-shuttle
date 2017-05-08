<#
    Retrieves publication orders from the publications locator system and uploads them to the  
    Government Printing Office FTP server.
#>

function Main() {
    try {

        $settings = GetSettings
        $orderData = RetrieveOrderData $settings
        $exportFilename = GetExportFileName $settings.testmode

        try {
            $orderData | Out-File $exportFilename -Encoding UTF8
            DoSftp $exportFilename $settings
        }
        finally {
            # Finally block to guarantee that clean up always takes place.
            Remove-Item $exportFilename
        }

    }
    catch [System.Exception] {
        ReportError "Send Orders" $_ $settings
    }
}


<#
    Performs a single SFTP operation, uploading $exportFilename to the GPO SFTP server.

    Notes:
        1.  The Putty software package (in particular, psftp) must be installed
        2.  The remote SFTP server's public key must have been accepted prior to
            the first run.

    @exportFilename - the file to be uploaded.

    @settings - Object containing ftp login credentials
#>
function DoSftp( $exportFilename, $settings ) {
    $server = $settings.ftp.server
    $userid = $settings.ftp.userid
    $password = $settings.ftp.password

    cmd /c echo put $exportFilename | psftp $userid@$server -pw $password -batch -bc
}


<#
    Retrieves a set of orders from the database.

    @settings - The overall configuration object.
#>
function RetrieveOrderData($settings) {
    # Set the @viewOnly paramter to 0 so the procedure clears the table afteward
    $xmlParam = new-object system.data.SqlClient.SqlParameter( "@viewOnly", [system.data.SqlDbType]::Bit )
    $xmlParam.value = 0
    $paramList = ,$xmlParam

    return ExecuteScalarXml $settings.ordersDatabase.connectionString "dbo.GPO_orderXML_download" "StoredProcedure" $paramList
}


<#
    Method for reading a single XML blob returned from a FOR XML query (or one embedded in a stored proc.)
    Use this instead of ExecuteScalar as ExecuteScalar will truncate XML at 2,033 characters.
    See: https://support.microsoft.com/en-us/help/310378/

    @connectionString - ADO.Net connection string for connecting to the database server.
            e.g. A connectionString value using Windows authention might look something like
            "Data Source=MY_SERVER\INSTANCE,PORT; Initial Catalog=MY_DATABASE; Integrated Security=true;"

    @commandText - The SQL Command to execute.

    @commandType - String containing the name of the type of SQL Command being executed.
                   May be any supported value of System.Data.CommandType

    @paramList - Iterable collection of SQLParameter objects.
#>
function ExecuteScalarXml( $connectionString, $commandText, $commandType, $paramList ) {

    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $command = new-object system.data.sqlclient.sqlcommand($commandText, $connection)
    $command.CommandType = $commandType

    # Attach the paramters to the command object.
    $paramList | ForEach-Object {
        $command.Parameters.Add( $_ ) | Out-Null
    }

    $connection.Open()

    # Powershell 2 doesn't have a using statement, so we do it by hand.
    $xmlBlob = ''
    try {
        $xmlReader = $command.ExecuteXmlReader();
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
    $explanationMessage = "Error occured in the '$stage' stage.`n$ex`n`n`nError at line: " +
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