# Dokploy Railway Template

Deploy Dokploy, a self-hosted deployment platform, on Railway with one click.

## What is Dokploy?

Dokploy is an open-source, self-hosted platform for managing deployments of web applications. It provides:

- Docker container management
- Application deployment from Git repositories
- Database management
- SSL certificate automation
- Resource monitoring

## Features

- ✅ One-click deployment on Railway
- ✅ Automatic Docker installation
- ✅ Health checks included
- ✅ Persistent storage for data
- ✅ Environment configuration
- ✅ SSL support

## Deployment

1. Click the "Deploy on Railway" button
2. Configure environment variables if needed
3. Add a persistent volume in Railway dashboard:
   - Create a volume and mount it to `/data`
   - This single volume will store all Dokploy and Docker data
4. Wait for deployment to complete (first deployment may take 3-5 minutes as Dokploy installs)
5. Access Dokploy at your Railway-generated URL on port 3000
6. Complete the initial setup

**Note:** Dokploy is installed at runtime on first launch to ensure Docker Swarm can properly initialize. Subsequent restarts will be faster.

## Environment Variables

- `PORT`: Port for Dokploy web interface (default: 3000, automatically set by Railway)
- `RAILWAY_ENVIRONMENT`: Environment type (default: production, set by Railway)
- `ADVERTISE_ADDR`: Docker Swarm advertise address (default: [::] for IPv6)
- `TRAEFIK_SSL_PORT`: HTTPS port (default: 443)
- `TRAEFIK_PORT`: HTTP port (default: 80)

**Note:** Railway automatically provides `RAILWAY_PUBLIC_DOMAIN` and `RAILWAY_PRIVATE_DOMAIN` for networking.

## Initial Setup

After deployment:

1. Navigate to your Railway-generated URL
2. Create an admin account
3. Start deploying your applications!

## Railway-Specific Features

This template is optimized for Railway with:
- **IPv6 Support**: Full dual-stack networking configuration
- **Private Networking**: Services can communicate via `*.railway.internal`
- **Persistent Storage**: Volumes for Docker and Dokploy configuration
- **Health Checks**: Automatic health monitoring
- **Auto-restart**: Configured restart policies

## Volume Configuration

Railway allows only one volume per service. After deployment, configure the volume in Railway dashboard:

### Required Volume:
- **Mount path:** `/data`
- **Purpose:** Stores all persistent data including:
  - Dokploy configuration and settings
  - Docker images, containers, and volumes
  - Traefik configuration and SSL certificates
  - Application deployments and databases

The entrypoint script automatically creates symlinks from standard locations to the `/data` volume.

**Important:** Without this volume, your data will be lost on redeploy!

## Networking on Railway

- External access: Via `RAILWAY_PUBLIC_DOMAIN` (HTTPS)
- Internal communication: Via `RAILWAY_PRIVATE_DOMAIN` (IPv6)
- Dokploy services: Accessible within the Railway project
- Traefik routing: Automatically configured for Railway's network

## Troubleshooting

### First Deployment Takes Long
The initial deployment installs Dokploy and configures Docker Swarm, which takes 3-5 minutes. Subsequent deployments are faster.

### Cannot Access Dokploy
- Ensure port 3000 is exposed in Railway settings
- Check the deployment logs for any errors
- Verify the public domain is properly configured

### Docker Swarm Issues
The template automatically handles Docker Swarm initialization with IPv6 support for Railway.

## Support

For issues with this template, please create an issue in this repository.
For Dokploy-specific support, visit [Dokploy Documentation](https://docs.dokploy.com)
For Railway-specific issues, check [Railway Documentation](https://docs.railway.app)

## License

This template is open source. Dokploy is licensed under its own terms.