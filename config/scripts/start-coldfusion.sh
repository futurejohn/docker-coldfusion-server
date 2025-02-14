#!/bin/sh

# start-coldfusion.sh (Refactored)

# POSIX-compliant shell script for ColdFusion initialization and management

# Helper functions

# Set default ports if not provided
CF_HOST_PORT="${CF_HOST_PORT:-8500}"
CF_DOCKER_PORT="${CF_DOCKER_PORT:-8500}" 

ADD_ONS_HOST_PORT="${ADD_ONS_HOST_PORT:-8995}"

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1"
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $1"
    fi
}

update_file() {
    sed -i "s|$2|$3|g" "$1"
}

check_env_var() {
    eval [ -n "\${$1+x}" ]
}

execute_cfm() {
    cfm_file="$1"
    password="${2:-admin}"
    
    # Handle special characters in password
    password=$(echo "$password" | sed 's/#/##/g')
    
    update_file "/opt/startup/coldfusion/$cfm_file" '<ADMIN_PASSWORD>' "\"$password\""
    curl "http://localhost:${CF_DOCKER_PORT}/ColdFusionDockerStartupScripts/$cfm_file"
}

runPostInstallConfigurationTest() {
    if [ "${RUN_POST_INSTALL_TEST:-false}" = "true" ]; then
        log_info "Running post-installation configuration test"
        curl "http://localhost:${CF_DOCKER_PORT}/postInstallConfigurationTest.cfm"
        log_info "Post-installation configuration test completed"
    else
        log_info "Skipping post-installation configuration test"
    fi
}

# METHODS

# CLI filename. Empty if not specified
filename="$2"

# Start ColdFusion in the foreground

start() {
    log_info "--- The start-coldfusion.sh is running ---"
    log_info "Starting ColdFusion initialization process"
    log_info "------------------------------------------"
    # log_info "Using ColdFusion port: ${CF_DOCKER_PORT}"

    if [ -e /opt/startup/disableScripts ]; then
        log_info "Skipping ColdFusion setup (scripts disabled)"
        startColdFusion 0
    else
        restartRequired=0
        #skipconfigurationwizard
        updateWebroot
        updatePassword
        updateLanguage
        setupSerialNumber
        startColdFusion 0  
        # Execute setup functions and update restart flag
        execute_setup_functions
        cleanupTestDirectories
        log_info "Restart required: $restartRequired"
        # Final action - Restart CF for changes to take effect        
        if [ $restartRequired = 1 ]; then
            startColdFusion 1
        fi
        echo 'Do not delete. Avoids script execution on container start' >  /opt/startup/disableScripts        
    fi

    log_info "ColdFusion initialization process completed."

    # Run the post-installation configuration test
    runPostInstallConfigurationTest

    # Listen to start a daemon
    listenToStartDaemon
}

execute_setup_functions() {
    setup_functions="installModules importCFsetup importModules importCAR setupExternalAddons setupExternalSessions invokeCustomCFM enableSecureProfile setDeploymentType setProfile"
    for func in $setup_functions; do
        log_info "Executing setup function: $func"
        $func
        tmpRestartRequired=$?
        restartRequired=$(( restartRequired | tmpRestartRequired ))
    done
}

listenToStartDaemon() {
    touch /opt/coldfusion/cfusion/logs/coldfusion-out.log
    log_info "Tailing ColdFusion logs"
    tail -f /opt/coldfusion/cfusion/logs/coldfusion-out.log
}

skipconfigurationwizard() {
    log_info "Skipping Configuration and Setting Wizard"
    update_file "/opt/coldfusion/cfusion/lib/adminconfig.xml" "<runsetupwizard>true</runsetupwizard>" "<runsetupwizard>false</runsetupwizard>"
}

startColdFusion() {
    if [ "$1" = 1 ]; then
        log_info "Restarting ColdFusion"
        # Stop ColdFusion
        /opt/coldfusion/cfusion/bin/coldfusion stop
        # Wait for complete stop
        while true; do
            status=$(/opt/coldfusion/cfusion/bin/coldfusion status)
            if echo "$status" | grep -q "Server is not running"; then
                log_info "ColdFusion stopped successfully"
                break
            fi
            log_info "Waiting for ColdFusion to stop..."
            sleep 5
        done
        # Small delay to ensure clean shutdown
        sleep 5
    else
        log_info "Starting ColdFusion"
    fi
 
    # Start ColdFusion Service
    /opt/coldfusion/cfusion/bin/coldfusion start
 
    # Wait for ColdFusion to be fully operational
    checkColdFusionStatus
    # Verify the start
    status=$(/opt/coldfusion/cfusion/bin/coldfusion status)
    if ! echo "$status" | grep -q "Server is running"; then
        log_error "Failed to start ColdFusion"
        exit 1
    fi
    log_info "ColdFusion is now running"
}

checkColdFusionStatus() {
    response=$(/opt/coldfusion/cfusion/bin/coldfusion status)
    version=$(/opt/coldfusion/cfusion/bin/cfinfo.sh -version)

    if [ "$response" = "Server is running" ]; then
        return 0
    else
        log_info "Checking server startup status: $response"
        log_info "ColdFusion Installation: $version"
        sleep 5
        checkColdFusionStatus
    fi
}

updateWebroot() {
    log_info "Updating webroot to /app"
    xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host -t elem -n ContextHolder -v "" \
        -i //ContextHolder -t attr -n "path" -v "" \
        -i //ContextHolder -t attr -n "docBase" -v "/app" \
        -i //ContextHolder -t attr -n "WorkDir" -v "/opt/coldfusion/cfusion/runtime/conf/Catalina/localhost/tmp" \
        -r //ContextHolder -v Context \
    /opt/coldfusion/cfusion/runtime/conf/server.xml
    log_info "Successfully updated webroot to /app"

    log_info "Configuring virtual directories"
    # Existing PreResources for CFIDE and cf_scripts
    xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host/Context -t elem -n ResourceHolder -v "" \
        -r //ResourceHolder -v Resources \
    /opt/coldfusion/cfusion/runtime/conf/server.xml

    # Add PreResources for various directories
    add_pre_resources "/cf_scripts" "/opt/coldfusion/cfusion/wwwroot/cf_scripts"
    add_pre_resources "/CFIDE" "/opt/coldfusion/cfusion/wwwroot/CFIDE"
    add_pre_resources "/WEB-INF" "/opt/coldfusion/cfusion/wwwroot/WEB-INF"
    add_pre_resources "/restplay" "/opt/coldfusion/cfusion/wwwroot/restplay"
    add_pre_resources "/ColdFusionDockerStartupScripts" "/opt/startup/coldfusion"
    
    # Add PostResources for /app/projects mounted at root
    xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host/Context/Resources -t elem -n PostResourcesHolder -v "" \
        -i //PostResourcesHolder -t attr -n "base" -v "/app/projects" \
        -i //PostResourcesHolder -t attr -n "className" -v "org.apache.catalina.webresources.DirResourceSet" \
        -i //PostResourcesHolder -t attr -n "webAppMount" -v "/" \
        -r //PostResourcesHolder -v PostResources \
    /opt/coldfusion/cfusion/runtime/conf/server.xml

    # Copy files to webroot
    # Ensure /app and /app/projects exist
    mkdir -p /app/projects
    cp -R /opt/coldfusion/cfusion/wwwroot/crossdomain.xml /app/
    chown -R cfuser /app /opt/startup/coldfusion

    log_info "Webroot configuration completed"
}

add_pre_resources() {
    mount_point="$1"
    base_path="$2"
    xmlstarlet ed -P -S -L -s /Server/Service/Engine/Host/Context/Resources -t elem -n PreResourcesHolder -v "" \
        -i //PreResourcesHolder -t attr -n "base" -v "$base_path" \
        -i //PreResourcesHolder -t attr -n "className" -v "org.apache.catalina.webresources.DirResourceSet" \
        -i //PreResourcesHolder -t attr -n "webAppMount" -v "$mount_point" \
        -r //PreResourcesHolder -v PreResources \
    /opt/coldfusion/cfusion/runtime/conf/server.xml
}

cleanupTestDirectories() {
    log_info "Cleaning up setup directories"
    
    # Remove virtual directory mapping from server.xml
    xmlstarlet ed -P -S -L -d '/Server/Service/Engine/Host/Context/Resources/PreResources[@webAppMount="/ColdFusionDockerStartupScripts"]' /opt/coldfusion/cfusion/runtime/conf/server.xml

    # Delete directory
    rm -rf /opt/startup/coldfusion
    log_info "Cleanup completed"
}

importCFsetup() {
    returnVal=0
    if [ -z "${importCFSettings+x}" ]; then
        log_info "No Settings to be imported"
    else
        cd /app || {
            log_error "Failed to change directory to /app"
            return 1
        }
        log_info "Importing CFsettings"
        export JAVA_HOME=/opt/coldfusion/jre
        /opt/coldfusion/config/cfsetup/cfsetup.sh alias cfusion /opt/coldfusion/cfusion
        
        if [ -z "${importCFSettingsPassphrase+x}" ]; then
            /opt/coldfusion/config/cfsetup/cfsetup.sh import all "$importCFSettings" cfusion
        else
            /opt/coldfusion/config/cfsetup/cfsetup.sh import all "$importCFSettings" cfusion -p="$importCFSettingsPassphrase"
        fi
        
        log_info "Imported CFsettings"
        returnVal=1
    fi
    return "$returnVal"
}

installModules() {
    if [ -z "${installModules+x}" ]; then
        log_info "No Modules to be installed" 
        return 0
    fi
    
    log_info "Installing Modules"
    export JAVA_HOME=/opt/coldfusion/jre
    echo "install ${installModules}" | /opt/coldfusion/cfusion/bin/cfpm.sh 
    log_info "Modules installed"
    return 0
}

importModules() {
    if [ -z "${importModules+x}" ]; then
        log_info "No Modules to be imported" 
        return 0
    fi
    
    log_info "Importing Modules"
    export JAVA_HOME=/opt/coldfusion/jre
    cd /app
    echo "import ${importModules}" | /opt/coldfusion/cfusion/bin/cfpm.sh 
    log_info "Modules imported"
    return 0
}

updatePassword() {
    if check_env_var password; then
        log_info "Updating password"
        log_info "Attempting to set password as $password"
        update_file "/opt/coldfusion/cfusion/lib/password.properties" "password=.*" "password=$password"
        update_file "/opt/coldfusion/cfusion/lib/password.properties" "encrypted=.*" "encrypted=false"
        chown cfuser /opt/coldfusion/cfusion/lib/password.properties
        log_info "Password updated successfully"
    else
        log_info "Skipping password update"
    fi
}

updateLanguage() {
    if check_env_var language; then
        log_info "Updating language"
        jvm_config="/opt/coldfusion/cfusion/bin/jvm.config"
        if grep -q "\-Duser.language=en" "$jvm_config"; then
            log_info "Replacing JVM argument"
            update_file "$jvm_config" "-Duser.language=en" "-Duser.language=$language"
        else
            log_info "Inserting JVM argument"
            update_file "$jvm_config" "java.args=-server" "java.args=-server -Duser.language=$language"
        fi
        log_info "Language updated successfully"
    else
        log_info "Skipping language update"
    fi
}

enableSecureProfile(){
    if check_env_var enableSecureProfile && [ "$enableSecureProfile" = true ]; then
        log_info "Attempting to enable secure profile"
        execute_cfm "enableSecureProfile.cfm" "${password:-admin}"
        log_info "Secure profile enabled"
        return 1
    else
        log_info "Secure Profile: Disabled"
        return 0
    fi
}

setDeploymentType() {
    if [ -z "${deploymentType+x}" ]; then
        log_info "Deployment Type not set, set to default (Development)"
        return 0
    fi
    
    log_info "Attempting to set deployment type"
    chmod 777 /opt/coldfusion/cfusion/lib/licenseinfo.properties
    chown cfuser /opt/coldfusion/cfusion/lib/licenseinfo.properties
    chgrp cfuser /opt/coldfusion/cfusion/lib/licenseinfo.properties
    # Update Password
    password_value=${password:-admin}
    password_value=$(echo "$password_value" | sed 's/#/##/g')
    
    sed -i -- 's/<ADMIN_PASSWORD>/"'"$password_value"'"/g' /opt/startup/coldfusion/setDeploymentType.cfm
    sed -i -- "s/<DEPLOYMENT_TYPE>/'${deploymentType}'/g" /opt/startup/coldfusion/setDeploymentType.cfm
    
    curl "http://localhost:${CF_DOCKER_PORT}/ColdFusionDockerStartupScripts/setDeploymentType.cfm"
    log_info "Deployment type set to ${deploymentType}"
    return 1
}

setProfile() {
    if [ -z "${profile+x}" ]; then
        log_info "Profile not set, set to default (Development Profile)"
        return 0
    fi
    
    log_info "Attempting to set profile"
    password_value=${password:-admin}
    password_value=$(echo "$password_value" | sed 's/#/##/g')
    
    profile_file="/opt/startup/coldfusion/setProfile.cfm"
    profile_with_ip_file="/opt/startup/coldfusion/setProfilewithIP.cfm"
    
    if [ -z "${allowedAdminIPList+x}" ]; then
        log_info "Allowed admin IP List not set"
        sed -i -- 's/<ADMIN_PASSWORD>/"'"$password_value"'"/g' "$profile_file"
        sed -i -- "s/<PROFILE_TYPE>/'${profile}'/g" "$profile_file"
        curl "http://localhost:${CF_DOCKER_PORT}/ColdFusionDockerStartupScripts/setProfile.cfm"
    else 
        log_info "Allowed admin IP List set"
        profile_lower=$(echo "$profile" | tr '[:upper:]' '[:lower:]')
        if [ "$profile_lower" = "production" ] || [ "$profile_lower" = "development" ]; then
            log_info "Allowed Admin IP List is set only for Production Secure Profile, you have chosen profile ${profile}"
        fi
        
        sed -i -- 's/<ADMIN_PASSWORD>/"'"$password_value"'"/g' "$profile_with_ip_file"
        sed -i -- 's/<ALLOWED_ADMINIPLIST>/"'"$allowedAdminIPList"'"/g' "$profile_with_ip_file"
        sed -i -- "s/<PROFILE_TYPE>/'${profile}'/g" "$profile_with_ip_file"
        curl "http://localhost:${CF_DOCKER_PORT}/ColdFusionDockerStartupScripts/setProfilewithIP.cfm"
    fi
    
    log_info "Profile set to ${profile}"
    return 1
}

checkAddonsStatus() {
    host="$1"
    port="$2"
    url="http://$1:$2/solr"
    responsecode=$(curl --write-out %{http_code} --silent --output /dev/null "${url}")
    max_attempts=10
    attempt=1

    while [ $attempt -le $max_attempts ]; do
        if nc -z "$host" "$port"; then
            log_info "Addons container is ready on $host:$port"
            return 0
        else
            log_info "Attempt $attempt: Waiting for addons container to be ready on $host:$port..."
            sleep 5
            attempt=$((attempt + 1))
        fi
    done

    log_error "Addons container did not become ready on $host:$port after $max_attempts attempts"
    return 1
}

setupExternalAddons(){
	returnVal=0
        if [ -z ${configureExternalAddons+x} ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] External Addons: Disabled"
        else
                if [ $configureExternalAddons = true ]; then

			echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Configuring External Addons"

                        # Update Password
                        if [ -z ${password+x} ]; then
                                sed -i -- 's/<ADMIN_PASSWORD>/"admin"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
                        else
                               if echo "$password" | grep -q "#"; then
                                   password=$(echo "$password" | sed 's/#/##/g')
                               fi
 
			       
				sed -i -- 's/<ADMIN_PASSWORD>/"'$password'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
                        fi

			# Update Addons Host
			_addonsHost="localhost"
			if [ -z ${addonsHost+x} ]; then
				sed -i -- 's/<ADDONS_HOST>/"localhost"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<ADDONS_HOST>/"'$addonsHost'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
				_addonsHost="$addonsHost"
			fi 
				
			# Update Addons Port
			_addonsPort="8989"
			if [ -z ${addonsPort+x} ]; then
				sed -i -- 's/<ADDONS_PORT>/8989/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<ADDONS_PORT>/'$addonsPort'/g' /opt/startup/coldfusion/enableExternalAddons.cfm
				_addonsPort="$addonsPort"
			fi

			# Update Addons Username
			if [ -z ${addonsUsername+x} ]; then
				sed -i -- 's/<ADDONS_USERNAME>/"admin"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<ADDONS_USERNAME>/"'$addonsUsername'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			fi

			# Update Addons Password
			if [ -z ${addonsPassword+x} ]; then
				sed -i -- 's/<ADDONS_PASSWORD>/"admin"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<ADDONS_PASSWORD>/"'$addonsPassword'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			fi

			# Update PDF Service name
			if [ -z ${addonsPDFServiceName+x} ]; then
				sed -i -- 's/<PDF_SERVICE_NAME>/"addonsContainer"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<PDF_SERVICE_NAME>/"'$addonsPDFServiceName'"/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			fi

			# Update PDF SSL
			if [ -z ${addonsPDFSSL+x} ]; then
				sed -i -- 's/<PDF_SSL>/false/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			else
				sed -i -- 's/<PDF_SSL>/'$addonsPDFSSL'/g' /opt/startup/coldfusion/enableExternalAddons.cfm
			fi

			checkAddonsStatus $_addonsHost $_addonsPort

			curl "http://localhost:8500/ColdFusionDockerStartupScripts/enableExternalAddons.cfm"

                        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] External Addons configured successfully"
                        returnVal=1
                else
                        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] External Addons: Disabled"
                fi
        fi

        return "$returnVal"
}

setupExternalSessions() {
    if [ -z "${configureExternalSessions+x}" ] || [ "$configureExternalSessions" != true ]; then
        log_info "External Session Storage: Disabled"
        return 0
    fi
    
    externalSessionsHost="${externalSessionsHost:-localhost}"
    externalSessionsPort="${externalSessionsPort:-6379}"
    
    log_info "Configuring external session storage on $externalSessionsHost:$externalSessionsPort"
    
    session_file="/opt/startup/coldfusion/enableSessionStorage.cfm"
    password_value="${password:-admin}"
    password_value=$(echo "$password_value" | sed 's/#/##/g')
    
    sed -i "s/<ADMIN_PASSWORD>/\"$password_value\"/g" "$session_file"
    sed -i "s/<REDIS_HOST>/\"$externalSessionsHost\"/g" "$session_file"
    sed -i "s/<REDIS_PORT>/\"$externalSessionsPort\"/g" "$session_file"
    sed -i "s/<REDIS_PASSWORD>/\"${externalSessionsPassword:-}\"/g" "$session_file"
    
    curl "http://localhost:${CF_DOCKER_PORT}/ColdFusionDockerStartupScripts/enableSessionStorage.cfm"
    log_info "External session storage configured successfully"
    
    return 1
}

setupSerialNumber() {
    returnVal=0
    license_file="/opt/coldfusion/cfusion/lib/license.properties"

    if check_env_var serial; then
        if [ -n "$serial" ]; then
            log_info "Updating serial key"
            update_file "$license_file" "^sn=Developer" "sn=$serial"
            log_info "Serial key updated successfully"
            returnVal=1
        else
            log_info "Empty Serial Key Provided, Not updating serial key"
        fi
    else
        log_info "Serial Key: Not Provided"
    fi

    if check_env_var previousSerial; then
        log_info "Updating previous serial key"
        update_file "$license_file" "^previous_sn=" "previous_sn=$previousSerial"
        log_info "Previous serial key updated successfully"
        returnVal=1
    else
        log_info "Previous Serial Key: Not Provided"
    fi

    return "$returnVal"
}

importCAR() {
    if [ "$(ls -A /data/*.car 2>/dev/null)" ]; then
        returnVal=1
    else
        returnVal=0
    fi

    if [ ! -d /data ]; then
        mkdir /data
        log_info "Created /data directory"
    fi

    chown -R cfuser /data
    log_info "Changed ownership of /data to cfuser"
    
    password_value="${password:-admin}"
    password_value=$(echo "$password_value" | sed 's/#/##/g')
    sed -i "s/<ADMIN_PASSWORD>/\"$password_value\"/g" /opt/startup/coldfusion/importCAR.cfm

    curl "http://localhost:${CF_DOCKER_PORT}/ColdFusionDockerStartupScripts/importCAR.cfm"
    log_info "CAR import process completed"

    return "$returnVal"
}

invokeCustomCFM(){
    if [ -z "${setupScript+x}" ]; then
        log_info "Skipping setup script invocation"
        return 0
    fi
    
    log_info "Invoking custom CFM: $setupScript"
    curl "http://localhost:${CF_DOCKER_PORT}/$setupScript"
    log_info "Custom CFM invocation completed"

    if [ "${setupScriptDelete:-false}" = true ]; then
        log_info "Deleting setupScript"	
        rm -rf "/app/$setupScript"
        log_info "SetupScript deleted"
    else
        log_info "Retaining setupScript in the webroot"
    fi

    return 1
}

info(){
    log_info "Retrieving ColdFusion version information"
    /opt/coldfusion/cfusion/bin/cfinfo.sh -version
}

cli(){
    if [ -z "${filename+x}" ]; then
        log_error "CLI needs a CFM file to execute, the file must be present in the webroot, /app"
        return
    fi
    
    if [ ! -d "/app" ]; then
        log_error "/app directory does not exist"
        return
    fi
    
    cd /app || return
    filepath="/app/${filename}"
    
    if [ -f "$filepath" ]; then
        log_info "Executing CFM file: $filename"
        /opt/coldfusion/cfusion/bin/cf.sh "$filename"
    else 
        log_error "CLI needs a CFM file to execute, the file must be present in the webroot, /app"
    fi
}

validateEulaAcceptance(){
    if [ -z "${acceptEULA+x}" ] || [ "$acceptEULA" != "YES" ]; then
        log_error "EULA needs to be accepted. Required environment variable, acceptEULA=YES"
        exit 1
    fi
}

help(){
    log_info "Displaying help information"
    cat << EOF
Supported commands: help, start, info, cli <.cfm>
Webroot: /app
CAR imports: CAR files present in /data will be automatically imported during startup
Required ENV Variables:
    acceptEULA=YES
Optional ENV variables: 
    serial=<ColdFusion Serial Key>
    previousSerial=<ColdFusion Previous Serial Key (Upgrade)>
    password=<Password>
    enableSecureProfile=<true/false(default)> 
    configureExternalSessions=<true/false(default)>
    externalSessionsHost=<Redis Host (Default:localhost)>
    externalSessionsPort=<Redis Port (Default:6379)>
    externalSessionsPassword=<Redis Password (Default:Empty)>
    configureExternalAddons=<true/false(default)>
    addonsHost=<Addon Container Host (Default: localhost)>
    addonsPort=<Addon Container Port (Default: 8993)>
    addonsUsername=<Solr username (Default: admin)>
    addonsPassword=<Solr password (Default: admin)>
    addonsPDFServiceName=<PDF Service Name (Default: addonsContainer)>
    addonsPDFSSL=<true/false(default)>
    setupScript=<CFM page to be invoked on startup. Must be present in the webroot, /app>
    setupScriptDelete=<true/false(default) Auto delete setupScript post execution>
    language=<ja/en (Default: en)>
    installModules=<Comma delimited list of modules to be installed by CF Package Manager,accepts 'all' for installing all the available packages>
    importCFSettings=<A JSON file containing the CF Settings to be imported . Must be present in the webroot, /app>
    importCFSettingsPassphrase=<Passphrase to import CF settings from an encrypted JSON file.>
    importModules=<A text file containing packages to be imported. Must be present in the webroot, /app>
    deploymentType=<Set deployment type of ColdFusion , by default it is 'Development'. Possible Values - Production,Staging,Testing,Disaster Recovery>
    profile=<Set profile of ColdFusion, by default it is 'Development'. Possible Values - Production,Production Secure>
    allowedAdminIPList=<Used to set a list of IP that are allowed to access ColdFusion Administrator, can be set only when the ColdFusion profile is Production Secure>
For more info , visit the official documentation of ColdFusion Docker images , https://helpx.adobe.com/coldfusion/using/docker-images-coldfusion.html
EOF
}

# METHODS END

case "$1" in
    "start")
        validateEulaAcceptance
        start
        ;;
    info)
        info
        ;;
    cli)
        validateEulaAcceptance
        cli
        ;;
    help)
        help
        ;;
    *)
        validateEulaAcceptance
        cd /opt/coldfusion/cfusion/bin/ || exit
        exec "$@"
        ;;
esac