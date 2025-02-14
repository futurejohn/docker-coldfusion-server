#!/bin/sh

# start-jetty.sh - for ColdFusion-Addons

# POSIX-compliant shell script for ColdFusion-Addons initialization and management

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

# METHODS

# Start ColdFusion in the foreground
start() {
    if [ -e /opt/startup/disableScripts ]; then
        log_info "Initial setup already completed, starting service directly"
    else
        # First-time setup
        log_info "Performing first-time setup..."
        
        # Update hostname to 0.0.0.0 : Accept connections from everywhere! Restrictions are placed in the docker environment instead
        log_info "Updating connector host to 0.0.0.0"
		# xmlstarlet ed -P -S -L --inplace -u '/Configure/Call[@name="addConnector"]/Arg/New/Set[@name="host"]/Property[@name="jetty.http.host"]/@default' -v 0.0.0.0 /opt/coldfusionaddonservices/etc/jetty.xml
        update_file "/opt/coldfusionaddonservices/start.ini" "# jetty.http.host=0.0.0.0" "jetty.http.host=0.0.0.0"
        
        # Provide appropriate permissions for files updated on hotfix installation
        log_info "Executing hotfix updates"
        chmod -R +x /opt/coldfusionaddonservices/webapps/PDFgServlet/Resources/bin
        
        # Provide ownership of the entire directory to cfuser
        log_info "Updating ownerships"
        chown -R cfuser /opt/coldfusionaddonservices/
        
        # Mark setup as complete
        touch /opt/startup/disableScripts
    fi

    # Always start the service, regardless of whether it's first time or not
    log_info "Starting ColdFusion-Addons via Jetty Server..."
    /opt/coldfusionaddonservices/cfjetty start

    # Always tail the logs
    log_info "Tailing start.log..."
    tail -f /opt/coldfusionaddonservices/logs/start.log
}

validateEulaAcceptance() {
    if [ -z "${acceptEULA+x}" ] || [ "$acceptEULA" != "YES" ]; then
        log_error "EULA needs to be accepted. Required environment variable, acceptEULA=YES"
        exit 1
    fi
}

help() {
    log_info "Supported commands: help, start <.cfm>"
    log_info "Required ENV Variables:
        acceptEULA=YES"
    log_info "Optional ENV Variables:
        solrUsername=<SOLR-USERNAME>
        solrPassword=<SOLR-PASSWORD>"
}

# METHODS END

case "$1" in
    "start")
        validateEulaAcceptance
        start
        ;;
    help)
        help
        ;;
    *)
        validateEulaAcceptance
        cd /opt/coldfusionaddonservices/
        exec "$@"
        ;;
esac
