#!/usr/bin/env bash
set -e

APP_DIR="/home/ubuntu/app"
cd "$APP_DIR"

: "${DOCKER_IMAGE:?Need to set DOCKER_IMAGE}"

# Optional: login to Docker Hub if using private images
if [ -n "${DOCKERHUB_USERNAME}" ] && [ -n "${DOCKERHUB_TOKEN}" ]; then
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
fi

# Pull latest image
docker-compose pull

# Restart container with latest image
docker-compose up -d --remove-orphans

# Cleanup old images
docker image prune -f

# Reload Nginx (if used)
sudo systemctl reload nginx || true

echo "✅ Deployment successful: $DOCKER_IMAGE"
