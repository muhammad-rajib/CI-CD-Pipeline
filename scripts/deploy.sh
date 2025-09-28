#!/usr/bin/env bash
set -e

APP_DIR="/home/ubuntu/app"
cd "$APP_DIR"

DOCKER_IMAGE="$1"
DOCKERHUB_USERNAME="$2"
DOCKERHUB_TOKEN="$3"

: "${DOCKER_IMAGE:?Need to set DOCKER_IMAGE}"

# Export for docker-compose
export DOCKER_IMAGE

# Login to Docker Hub if private
if [ -n "${DOCKERHUB_USERNAME}" ] && [ -n "${DOCKERHUB_TOKEN}" ]; then
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
fi

# Pull latest Docker image and restart container
docker-compose pull
docker-compose up -d --remove-orphans

# Cleanup old images
docker image prune -f

# Reload Nginx if used
sudo systemctl reload nginx || true

echo "✅ Deployment successful: $DOCKER_IMAGE"
