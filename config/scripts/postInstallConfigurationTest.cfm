<!--- config/scripts/postInstallConfigurationTest.cfm --->
<cfscript>
    // Reusable logging function
    function logMethod(required string message, string type = "INFO") {
        writeOutput("#dateTimeFormat(now(), "yyyy-mm-dd HH:nn:ss")# [#type#] #message#" & chr(13) & chr(10));
    }

    // Info logging function
    function logInfo(required string message) {
        logMethod(message, "INFO");
    }

    // Error logging function
    function logError(required string message) {
        logMethod(message, "ERROR");
    }

    logInfo("Starting post-installation configuration tests");

    // Test CF Admin login
    adminObj = createObject("component","CFIDE.adminapi.administrator");
    adminPassword = server.system.environment.password;
    if (adminPassword == "") {
        logError("Admin password is not set in environment variables. Aborting tests.");
        abort;
    }

    try {
        adminObj.login(adminPassword);
        logInfo("Successfully logged in with CF Admin password");
    } catch (any e) {
        logError("Failed to log in with CF Admin password: #e.message#");
        abort;
    }

    // List Data Sources
    logInfo("Listing configured data sources");
    datasource = createObject("component", "CFIDE.adminapi.datasource");
    
    try {
        dsources = datasource.getDatasources();
        if (structCount(dsources) > 0) {
            for (ds in dsources) {
                dsInfo = dsources[ds];
                logInfo("Data Source: #ds#");
                logInfo("Driver: #dsInfo.driver#");
                // Safely output dsInfo structure
                for (key in dsInfo) {
                    if (structKeyExists(dsInfo, key) && isSimpleValue(dsInfo[key])) {
                        logInfo("  #key#: #dsInfo[key]#");
                    }
                }
                logInfo("Data Source #ds# of listed successfully");
            }
            logInfo("Total data sources listed: #structCount(dsources)#");
            logInfo("Test data sources configuration completed successfully");
        } else {
            logInfo("No data sources configured");
        }
    } catch (any e) {
        logError("Error listing data sources: #e.message#");
        logError("Error detail: #e.detail#");
    }

    // Test Mail Server Configuration
    logInfo("Testing mail server configuration");
    mailObj = createObject("component", "CFIDE.adminapi.mail");
    try {
        mailSettings = mailObj.getMailServers();
        if (arrayLen(mailSettings) > 0) {
            logInfo("Mail server configured: #mailSettings[1].server#:#mailSettings[1].port#");
            
            // Send a test email
            try {
                mailService = new mail(
                    to = "test@example.com",
                    from = "coldfusion@example.com",
                    subject = "ColdFusion Mail Test",
                    body = "This is a test email from ColdFusion to verify the mail configuration."
                );
                mailService.send();
                logInfo("Test email sent successfully. Please check Mailhog interface to confirm.");
            } catch (any e) {
                logError("Error sending test email: #e.message#");
                logError("Error detail: #e.detail#");
            }
        } else {
            logError("No mail server configured");
        }
    } catch (any e) {
        logError("Error retrieving mail server configuration: #e.message#");
    }

    // Test PDF Generation
    logInfo("Testing PDF generation");
    try {
        pdfFileName = "test_#createUUID()#.pdf";
        pdfFilePath = getTempDirectory() & pdfFileName;
        
        savecontent variable="pdfContent" {
            writeOutput('
                <cfhtmltopdf name="pdfTest">
                    <cfoutput>
                        <h1>PDF Generation Test</h1>
                        <p>Generated at #datetimeformat(now())#</p>
                        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam nec purus nec nunc ultricies ultricies.</p>
                        <p>Nullam nec purus nec nunca ultricies ultricies. Nullam nec purus nec nunc ultricies ultricies.</p>
                        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam nec purus nec nunc ultricies ultricies.</p>
                    </cfoutput>
                </cfhtmltopdf>
            ');
        }
        
        fileWrite(pdfFilePath, pdfContent);
        
        if (fileExists(pdfFilePath)) {
            pdfSize = getFileInfo(pdfFilePath).size;
            if (pdfSize > 0) {
                logInfo("PDF generation successful. File size: #pdfSize# bytes");
            } else {
                logError("PDF generation failed: File created but is empty");
            }
            fileDelete(pdfFilePath);
        } else {
            logError("PDF generation failed: File not created");
        }
    } catch (any e) {
        logError("Error generating PDF: #e.message#");
        logError("Error detail: #e.detail#");
    }

    // Test Solr Configuration
    logInfo("Testing Solr configuration");
    try {
        // Check if the test collection exists and delete it if it does
        cfcollection(action="list", name="collectionList");
        existingCollections = valueList(collectionList.name);
        
        if (listFindNoCase(existingCollections, "test")) {
            cfcollection(action="delete", collection="test");
            logInfo("Existing 'test' collection deleted");
        }

        // Create a new test collection
        cfcollection(action="create", collection="test", path="");
        logInfo("Solr test collection created successfully");

        // List collections to confirm creation
        cfcollection(action="list", name="collectionList");
        if (isQuery(collectionList) && collectionList.recordCount > 0) {
            logInfo("Solr collections listed successfully. Total collections: #collectionList.recordCount#");
        } else {
            logError("No Solr collections found after creation");
        }

        // Create a temporary directory for test data
        tempDir = getTempDirectory() & "solr_test_" & createUUID();
        directoryCreate(tempDir);
        logInfo("Created temporary directory for Solr test data: #tempDir#");

        // Create some test files
        fileWrite(tempDir & "/test1.txt", "This is a test file for Solr indexing. It contains some sample content.");
        fileWrite(tempDir & "/test2.txt", "Another test file with different content for Solr to index and search.");
        fileWrite(tempDir & "/test3.txt", "A third test file to ensure we have multiple documents in our Solr index.");
        logInfo("Created test files in the temporary directory");

        // Create an index using the test files
        cfindex(action="update", collection="test", type="path", key="#tempDir#", extensions=".txt");
        logInfo("Solr index created successfully using test files");

        // Add a delay to allow indexing to complete
        sleep(5000); // 5 seconds delay
        logInfo("Waited 5 seconds for indexing to complete");

        // Perform a search to verify the index
        cfsearch(collection="test", criteria="test", name="searchResult");
        if (isQuery(searchResult) && searchResult.recordCount > 0) {
            logInfo("Solr search successful. Total results: #searchResult.recordCount#");
            // Log the first few results
            for (i = 1; i <= min(searchResult.recordCount, 3); i++) {
                logInfo("Search result #i#: #searchResult.title[i]#");
            }
        } else {
            logError("No results found in Solr search");
            // Log more details about the search
            logInfo("Search criteria: 'test'");
            logInfo("Collection name: 'test'");
            logInfo("Number of documents indexed: #directoryList(tempDir, false, "name", "*.txt").recordCount#");
        }

        // Clean up: delete the temporary directory and its contents
        directoryDelete(tempDir, true);
        logInfo("Cleaned up temporary test directory");

        // Delete the test collection
        cfcollection(action="delete", collection="test");
        logInfo("Deleted test Solr collection");

    } catch (any e) {
        logError("Error testing Solr configuration: #e.message#");
        logError("Error detail: #e.detail#");
        logError("Error type: #e.type#");
        
        // Ensure cleanup in case of error
        if (isDefined("tempDir") && directoryExists(tempDir)) {
            try {
                directoryDelete(tempDir, true);
                logInfo("Cleaned up temporary test directory after error");
            } catch (any cleanupError) {
                logError("Failed to clean up temporary directory: #cleanupError.message#");
            }
        }
        
        // Attempt to delete the test collection in case of error
        try {
            cfcollection(action="delete", collection="test");
            logInfo("Deleted test Solr collection after error");
        } catch (any deleteError) {
            logError("Failed to delete test Solr collection: #deleteError.message#");
        }
    }

    logInfo("Post-installation configuration tests completed");
</cfscript>
