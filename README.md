# pubs-locator-shuttle
Scripts to transfer data between the publications locator and the Government Printing Office.

## Prerequisites

* **[Putty](http://www.chiark.greenend.org.uk/~sgtatham/putty/)** (specifically, _psftp_) must be installed, and available on the path.
* **pstftp** must have been run manually at least once and the remote server's ssh fingerprint accepted.

## order-uploader
Retrieves publication orders from the publications locator and uploads them to the  
GPO FTP server.

## report-downloader
Retrieves reports from the GPO FTP server and stores them in the publications locator.

| Report File Name   | Description |
| ------------------ | ----------- |
| InventoryReport    | Inventory of the number of each type of report available at GPO. |
| FullfillmentReport | Order fulfillment status |

File names for download from the GPO SFTP server follow the format of

    <report_name>-yyyyMMDdd.xml

e.g. InventoryReport-20170503.xml would be the Inventory report for May 3, 2017


## Configuration

Both scripts use the same configuration dta, an XML file named settings.xml

```xml
<!--
    The settings data structure.

    @testmode - If present and set to any value other than '0', the scripts are run in
                a testing mode.
 -->
<settings testmode="1">
    <!--
        @connectionString - Contains the connection string with credentials for logging in
                            to the pubs locator's database.
    -->
    <ordersDatabase server="SERVER\INSTANCE,PORT" database="DATABASE" />

    <!--
        Credentials for logging in to the GPO's SFTP server.

        @server - The sftp server's fully-qualified host name. Do not include a protocol.

        @userid - credentials for logging in to @server.

        @password - credentials for logging in to @server.

        @uploadPath - path for uploading files to the remote server. If not specified, / is assumed.

        @downloadPath - path to download from. If not specified, / is assumed.
    -->
    <ftp server="" userid="" password="" uploadPath="" downloadPath="" />

    <!--
        Email server

        @server - fully qualifified host name of the email server.
    -->
    <email server="MAILSERVER" />

    <!--
        Information to use when emailing an error report.

        @from - the address error reports will be seen as coming from. Should be in the form of
                user@domain.gov.

        @to - email address of the error report recipient (i.e. Who does it go to). Should be in the form of
              user@domain.gov.

        @subjectLine - the error report email's subject line.
    -->
    <errorReporting from="EMAIL_ADDRESS" to="EMAIL_ADDRESS" subjectLine="Error Report" />
</settings>
```

### Testing Mode
If the testmode attribute is set to any value other than '0', the scripts are run in a
testing mode.  At present, this means that the file for upload to the GPO's FTP server has
the string "NCI-TEST-" prepended to its namee.
