<!--- configure/scripts/configureColdFusion.cfm --->
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

    logInfo("Starting ColdFusion configuration process");

    // Set the CF Admin password explicitly
    adminObj = createObject("component","CFIDE.adminapi.administrator");
    adminPassword = server.system.environment.password;
    if (adminPassword == "") {
        logError("Admin password is not set in environment variables. Aborting configuration.");
        abort;
    }

    // Login with the new password
    adminObj.login(adminPassword);
    logInfo("Successfully logged in with new CF Admin password");

    // set mail server settings
    mailSettings = createObject("component","CFIDE.adminapi.mail");
    mailSettings.setMailServer(
        server="mailpit",
        port=1025,
        username="",
        password=""
    );
    logInfo("Mail server configured");

    logInfo("ColdFusion configuration process completed");
</cfscript>
