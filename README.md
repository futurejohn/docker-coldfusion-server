# ColdFusion Docker Development Environment

A Docker-based development environment for Adobe ColdFusion 2023, featuring:
- ColdFusion 2023 server with latest updates
- ColdFusion add-on services (PDF, Solr)
- Mail testing server (Mailpit)
- Automated configuration and setup

## Requirements

- Docker Desktop for Windows or macOS
  - Enable "Use Rosetta for x86/amd64 emulation" for Apple Silicon Macs
  - Recommended settings: 8GB+ RAM, 4+ CPUs
- Git
- VSCode (recommended)

## Quick Start

1. Clone the repository
2. Copy `.env.example` to `.env` and adjust settings as needed
3. Build and start the containers:
```shell
docker compose build --no-cache && docker compose up -d
```

Access services at:
- ColdFusion server: http://localhost:8500
- ColdFusion administrator: http://localhost:8500/CFIDE/administrator
- Mail testing interface: http://localhost:8025

## Project Structure

```
.
├── .dockerignore
├── .editorconfig
├── .env.example
├── .gitattributes
├── .gitignore
├── Dockerfile                                  # CF server image definition
├── README.md
├── compose.yaml                                # Docker compose configuration
├── config                                      # Configuration files
│   ├── imports                                 # CF Admin import files
│   │   ├── CFSettings.json
│   │   └── modules.txt
│   └── scripts                                 # Startup and config scripts
│       ├── configure-coldfusion.sh
│       ├── configureColdFusion.cfm
│       ├── postInstallConfigurationTest.cfm
│       ├── start-coldfusion.sh
│       └── start-jetty.sh
├── data                                        # Persistent data storage
│   └── .gitkeep
└── logs                                        # Log directory
    ├── .gitkeep
    ├── api-manager_logs
    ├── coldfusion-addons_logs
    ├── coldfusion-performance_logs
    └── coldfusion-server_logs
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and adjust:
- `CF_ADMIN_PASSWORD`: ColdFusion administrator password
- `PROJECTS_PATH`: Local path to your CF projects
- `RESTART`: Container restart policy (default: "no")

### ColdFusion Settings

- Server configuration: `config/imports/CFSettings.json`
- Module installation: `config/imports/modules.txt`
- Custom scripts: `config/scripts/configureColdFusion.cfm`

### ColdFusion Archive (.car) Files

#### Overview

ColdFusion Archive (`.car`) files are encrypted configuration bundles that store ColdFusion server settings. They're particularly useful for automating server configuration in Docker environments by allowing you to:

- Automatically configure datasources
- Persist server settings across container rebuilds
- Standardize configuration across development environments
- Automate deployment of server settings

#### Usage in Docker

This project automatically loads any `.car` files placed in the `./data` directory when the ColdFusion container starts. The process:

1. Container starts up
2. Scans `/data` directory for `.car` files
3. Automatically imports settings from any found `.car` files
4. Restarts ColdFusion service to apply settings

#### Creating a CAR File

1. Access the ColdFusion Administrator (http://localhost:8500/CFIDE/administrator)

2. Navigate to "Packaging & Deployment" section

3. Create new archive:
   - Click "Create Archive"
   - Enter a name (e.g., "ProjectSettings")
   - **Disable pop-up blocker** for next steps

4. Select settings to archive:
   - Option 1: Click "Select All" for all server settings
   - Option 2: Select specific settings (e.g., only datasources)

5. Build the archive:
   - Click "Build"
   - Choose `/data` as destination directory
   - Name the file (e.g., "ProjectSettings.car")

#### Implementation Example

Here's a typical workflow for configuring a datasource:

1. Configure datasource in CF Administrator:
```
Name: Project
Database: Project
Server: sql
Port: 1433
Username: sa
Password: your_password
```

2. Create CAR file with datasource settings

3. Place CAR file in `./data` directory

4. Rebuild containers:
```bash
docker compose down
docker compose up -d
```

#### Important Considerations

1. **Service Restart Required**: When a CAR file is applied, the ColdFusion service must restart to implement the settings. This adds to container startup time.

2. **Settings Updates**: Any changes to CF Administrator settings must be re-archived to persist across container rebuilds.

3. **File Location**: CAR files must be placed in the `./data` directory to be automatically applied.

4. **Security Considerations**: 
   - CAR files are not encrypted archives - they're standard archives containing server configurations
   - While datasource passwords within the CAR file are encrypted, the decryption keys are included in the same file
   - Due to this design, CAR files should be treated as sensitive configuration files
   - Implement appropriate access controls and security measures:
     - Restrict file permissions to necessary users only
     - Store in secure locations with controlled access
     - Consider using environment variables for sensitive credentials instead
     - Use secure transfer methods when moving files between environments

5. **Version Control Considerations**:
   - Generally avoid committing CAR files to version control
   - If version control is required:
     - Use private repositories with restricted access
     - Consider using git-crypt or similar tools for encrypting sensitive files
     - Document clear procedures for handling and distributing CAR files
     - Maintain an audit trail of file access and usage

#### Troubleshooting

- Verify CAR file permissions are correct
- Check container logs for import status
- Ensure file is placed in correct directory
- Confirm ColdFusion service restarts after import
- Monitor CF Administrator for successful settings application

## Basic Usage

### Create Container
```shell
docker compose up -d
```

### View Logs
```shell
docker compose logs -f
```

### Start Existing Container
```shell
docker compose start
```

### Stop Existing Container
```shell
docker compose stop
```

### Restart Existing Container
```shell
docker compose restart
```

### Remove Container
```shell
docker compose down
```

### Rebuild Containers
```shell
docker compose down -v
docker compose build --no-cache
docker compose up -d
```

## Development Workflow

1. Mount your CF projects directory in `.env`: `PROJECTS_PATH=/path/to/projects`
2. Access your projects via `http://localhost:8500/your-project`
3. Use Mailpit (http://localhost:8025) to test email functionality
4. Monitor logs in the `logs/` directory

## Troubleshooting

- If containers fail to start, check Docker resource allocation
- For ARM Macs, ensure Rosetta emulation is enabled
- View logs with `docker compose logs -f [service-name]`
- Check mounted volumes have correct permissions