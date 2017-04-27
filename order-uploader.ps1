<#
    Retrieves publication orders from the publications locator and uploads them to the  
    Government Printing Office FTP server.
#>

function Main() {
    try {

        $settings = GetSettings
        $orderData = RetrieveOrderData $settings
        $exportFilename = GetExportFileName $settings.testmode
        $orderData | Out-File $exportFilename
        DoSftp $exportFilename $settings

        # Clean up
        Remove-Item $exportFilename
    }
    catch [System.Exception] {
        ReportError "Send Orders" $_ $settings
    }
}


function DoSftp( $exportFilename, $settings ) {
    $server = $settings.ftp.server
    $userid = $settings.ftp.userid
    $password = $settings.ftp.password

    cmd /c echo put $exportFilename | psftp $userid@$server -pw $password -batch -bc
}


function RetrieveOrderData($settings) {
    # TODO Add parameter viewOnly, set to 0
    return ExecuteScalarXml $settings.ordersDatabase.connectionString "dbo.GPO_orderXML_download"
}


<#
    Method for reading a single XML blob returned from a FOR XML query (or one embedded in a stored proc.)
    Use this instead of ExecuteScalar as ExecuteScalar will truncate XML at 2,033 characters.
    See: https://support.microsoft.com/en-us/help/310378/

    @param $connectionString - ADO.Net connection string for connecting to the database server.
    e.g. A connectionString value using Windows authention might look something like
         "Data Source=MY_SERVER\INSTANCE,PORT; Initial Catalog=MY_DATABASE; Integrated Security=true;"
#>
function ExecuteScalarXml( $connectionString, $query ) {

    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $command = new-object system.data.sqlclient.sqlcommand($query,$connection)
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
    $explanationMessage = "Error occured in the '$stage' stage.`n$ex"

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