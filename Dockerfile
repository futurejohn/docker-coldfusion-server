# Dockerfile

# Use the official Adobe ColdFusion 2023 image as the base
# TODO: Replace 'latest' with specific version number for production builds
# currently using Update 12
FROM adobecoldfusion/coldfusion2023

# Add static metadata labels that don't change frequently
LABEL description="ColdFusion 2023 Server Docker Image" \
      version="0.0.1"

### Platform-Specific Configuration

# Set OS environment variables
ARG CF_ADMIN_PASSWORD

ENV JAVA_HOME=/opt/coldfusion/jre
ENV PATH=${JAVA_HOME}/bin:${PATH} \
    BASE_CONNECT_TIMEOUT=60000 \
    BASE_READ_TIMEOUT=60000 \
    BASE_CFPM_TIMEOUT=300 \
    TZ="America/New_York"

# Configure platform-specific timeouts
RUN if [ "$(uname -m)" != "x86_64" ]; then \
        echo "Detected non-x86_64 architecture, adjusting timeouts for emulation"; \
        export JAVA_TOOL_OPTIONS="-Dsun.net.client.defaultConnectTimeout=120000 -Dsun.net.client.defaultReadTimeout=120000"; \
        export CFPM_TIMEOUT=600; \
    else \
        echo "Detected x86_64 architecture, using standard timeouts"; \
        export JAVA_TOOL_OPTIONS="-Dsun.net.client.defaultConnectTimeout=$BASE_CONNECT_TIMEOUT -Dsun.net.client.defaultReadTimeout=$BASE_READ_TIMEOUT"; \
        export CFPM_TIMEOUT=$BASE_CFPM_TIMEOUT; \
    fi

### Certificate Configuration

# Install system certificates and tools first
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    netcat-openbsd \
    curl \
    fontconfig && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Ensure timezone is properly set
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

### ColdFusion Configuration

# Step 1: Verify network connectivity before updates

RUN echo "Verifying network connectivity..." && \
    for i in $(seq 1 3); do \
        if curl -v https://cfmodules.adobe.com; then \
            echo "Network connectivity verified on attempt $i"; \
            break; \
        elif [ "$i" -eq 3 ]; then \
            echo "Failed to verify network connectivity after 3 attempts"; \
            exit 1; \
        else \
            echo "Attempt $i failed, retrying..."; \
            sleep 10; \
        fi \
    done

# Step 2: Update CFPM with retry mechanism

RUN CFPM_TIMEOUT=${BASE_CFPM_TIMEOUT:-300} && \
    for i in $(seq 1 3); do \
        echo "Attempt $i of 3: Updating CFPM repository path..." && \
        if timeout "${CFPM_TIMEOUT}" /opt/coldfusion/cfusion/bin/cfpm.sh updaterepopath https://cfmodules.adobe.com/cf2023/bundlesdependency.json; then \
            echo "CFPM repository update successful"; \
            break; \
        elif [ "$i" -eq 3 ]; then \
            echo "Failed to update CFPM repository after 3 attempts"; \
            exit 1; \
        else \
            echo "Update attempt $i failed, retrying..."; \
            sleep 30; \
        fi \
    done

# Step 3: Display initial version

RUN echo "Current ColdFusion version:" && \
    /opt/coldfusion/cfusion/bin/cfinfo.sh -version

# Step 4: Update ColdFusion and packages with retry logic

RUN for i in $(seq 1 6); do \
        echo "Attempt $i of 6: Updating ColdFusion and packages..." && \
        if yes | /opt/coldfusion/cfusion/bin/cfpm.sh update all; then \
            echo "Update successful"; \
            break; \
        elif [ "$i" -eq 6 ]; then \
            echo "Failed to update after 6 attempts"; \
            exit 1; \
        else \
            echo "Update attempt $i failed, retrying..."; \
            sleep 60; \
        fi \
    done

# Step 5: # Verify final version and installation

RUN echo "Updated ColdFusion version:" && \
    /opt/coldfusion/cfusion/bin/cfinfo.sh -version && \
    echo "Verifying installation..." && \
    /opt/coldfusion/cfusion/bin/cfpm.sh list installed

### Application Setup

# Copy and configure scripts with proper permissions
COPY config/scripts/configure-coldfusion.sh /opt/startup/configure-coldfusion.sh
# We can rename this...to copy the minimal startup script for runtime
COPY config/scripts/minimal-start-coldfusion.sh /opt/startup/start-coldfusion.sh
COPY config/scripts/configureColdFusion.cfm /app/
COPY config/scripts/postInstallConfigurationTest.cfm /app/
COPY config/imports/CFSettings.json /app/
COPY config/imports/modules.txt /app/

# COPY config/scripts/start-minimal.sh /opt/startup/start-coldfusion.sh

# Set permissions in a single layer
RUN chmod +x /opt/startup/start-coldfusion.sh \
    /opt/startup/configure-coldfusion.sh \
    /app/configureColdFusion.cfm \
    /app/postInstallConfigurationTest.cfm \
    /app/CFSettings.json \
    /app/modules.txt

# Set environment variables for ColdFusion configuration

ENV acceptEULA=YES \
    password=${CF_ADMIN_PASSWORD} \
    language=en \
    installModules=all \
    setupScript=configureColdFusion.cfm \
    setupScriptDelete=false \
    importCFSettings=CFSettings.json \
    deploymentType=Development \
    profile=Development

# Run the configuration script

RUN /opt/startup/configure-coldfusion.sh

# Add build-specific metadata at the end to improve caching
ARG BUILD_DATE
ARG BUILD_COMMIT
LABEL build_date=$BUILD_DATE \
      build_commit=$BUILD_COMMIT
