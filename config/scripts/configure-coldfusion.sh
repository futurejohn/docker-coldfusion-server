#!/bin/sh

# Variables
CF_HOST_PORT="${CF_HOST_PORT:-8500}"
CF_DOCKER_PORT="${CF_DOCKER_PORT:-8500}" 

# Helper functions
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

checkColdFusionStatus() {
    max_attempts=30  # 5 minutes total with 10s sleep
    attempt=1

    while [ $attempt -le $max_attempts ]; do
        response=$(/opt/coldfusion/cfusion/bin/coldfusion status)
        version=$(/opt/coldfusion/cfusion/bin/cfinfo.sh -version)

        if [ "$response" = "Server is running" ]; then
            return 0
        else
            log_info "Attempt $attempt of $max_attempts: Checking server startup status: $response"
            log_info "ColdFusion Installation: $version"
            sleep 10
            attempt=$((attempt + 1))
        fi
    done

    log_error "ColdFusion server failed to start after $max_attempts attempts"
    return 1
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

# Skip configuration wizard
# log_info "Skipping Configuration and Setting Wizard"
# update_file "/opt/coldfusion/cfusion/lib/adminconfig.xml" \
#     "<runsetupwizard>true</runsetupwizard>" \
#     "<runsetupwizard>false</runsetupwizard>"

validateEulaAcceptance(){
    if [ -z "${acceptEULA+x}" ] || [ "$acceptEULA" != "YES" ]; then
        log_error "EULA needs to be accepted. Required environment variable, acceptEULA=YES"
        exit 1
    fi
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
        log_info "Skipping language update - no language provided. Using English as the default."
    fi
}

update_jvm_config() {
    log_info "Updating JVM configuration"
    jvm_config="/opt/coldfusion/cfusion/bin/jvm.config"

    # Install fontconfig for PDF generation
    log_info "Installing fontconfig package"
    apt-get update && apt-get install -y fontconfig

    # Backup original config
    cp "$jvm_config" "${jvm_config}.bak"
    log_info "Created backup of jvm.config"

    # Update java.home path
    log_info "Updating java.home path"
    sed -i 's|java.home=../../jre/Contents/Home|java.home=/opt/coldfusion/jre|' "$jvm_config"

    # Update java.args to include required exports
    log_info "Updating java.args with required exports"
    sed -i 's|java.args=\(.*\)|java.args=\1 --add-exports=java.desktop/sun.awt.image=ALL-UNNAMED --add-exports=java.desktop/sun.java2d=ALL-UNNAMED --add-exports=java.desktop/sun.font=ALL-UNNAMED|' "$jvm_config"

    # Verify updates
    if grep -q "java.home=/opt/coldfusion/jre" "$jvm_config" && \
       grep -q "sun.font=ALL-UNNAMED" "$jvm_config"; then
        log_info "JVM configuration updated successfully"
        return 0
    else
        log_error "Failed to update JVM configuration"
        return 1
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

execute_configuration_functions(){
    configuration_functions="
        validateEulaAcceptance
        updatePassword
        setupSerialNumber
        updateLanguage
        update_jvm_config
        updateWebroot"
    for func in $configuration_functions; do
        log_info "Executing configuration function: $func"
        $func
        tmpRestartRequired=$?
        restartRequired=$(( restartRequired | tmpRestartRequired ))
    done
}

execute_live_configuration_functions(){
    live_configuration_functions="
        enableSecureProfile
        setDeploymentType
        setProfile
        importModules
        installModules"
    for func in $live_configuration_functions; do
        log_info "Executing live configuration function: $func"
        $func
        tmpRestartRequired=$?
        restartRequired=$(( restartRequired | tmpRestartRequired ))
    done
}

# ==========================================================================
# ==========================================================================
# ==========================================================================


log_info "--- The configure-coldfusion.sh is running ---"
log_info "------------------------------------------"
log_info "Starting ColdFusion initialization process"
log_info "------------------------------------------"
# Execute all build-time configurations
log_info "Starting build-time configuration..."
execute_configuration_functions
# The following configurations require the server to be running.
log_info "Starting ColdFusion Server..."
startColdFusion 0
execute_live_configuration_functions
log_info "Build-time configuration completed"
