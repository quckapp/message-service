# Environment Configuration

This folder contains environment-specific configuration files for the Message Service.

## Available Environments

| File | Environment | Description |
|------|-------------|-------------|
| `dev.env` | Development | Local development with debug logging |
| `test.env` | Test | Automated testing with isolated databases |
| `staging.env` | Staging | Pre-production environment |
| `prod.env` | Production | Production environment with secrets from vault |
| `docker.env` | Docker | Docker Compose local development |

## Usage

### Local Development

```bash
cp envs/dev.env .env
mix phx.server
```

### Docker Development

```bash
docker-compose --env-file envs/docker.env up
```

## Service-Specific Variables

### Message Configuration

- `MAX_MESSAGE_LENGTH` - Maximum message character length
- `MESSAGE_RETENTION_DAYS` - How long to keep messages
- `MESSAGE_EDIT_WINDOW_MINUTES` - Time window for editing messages

### File Attachments (MinIO/S3)

- `MAX_ATTACHMENT_SIZE_MB` - Maximum file size in MB
- `MAX_ATTACHMENTS_PER_MESSAGE` - Maximum files per message
- `MINIO_ENDPOINT` - MinIO/S3 endpoint
- `MINIO_ACCESS_KEY` - Access key
- `MINIO_SECRET_KEY` - Secret key
- `MINIO_BUCKET` - Bucket name
- `MINIO_USE_SSL` - Enable SSL (true/false)
