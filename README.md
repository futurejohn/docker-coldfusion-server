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

## Basic Usage

### Start Environment
```shell
docker compose up -d
```

### View Logs
```shell
docker compose logs -f
```

### Stop Environment
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