# 🚀 FastAPI Deployment Guide on EC2 with CI/CD

This guide explains how to deploy a FastAPI app on **AWS EC2** using **GitHub Actions CI/CD**, Docker, Nginx, Namecheap, and Cloudflare. SSL is handled via **Cloudflare Flexible SSL** or **Certbot**.

---

## **1. Prerequisites**

- AWS EC2 instance (Ubuntu 22.04+ recommended)
- EC2 Security Group with ports: 22, 80, 443 open
- Docker & Docker Compose installed on EC2
- GitHub repository with FastAPI project
- GitHub Actions enabled
- Docker Hub account
- Domain purchased from Namecheap (e.g., `mdrajib.xyz`)
- Cloudflare account (optional, recommended for CDN/SSL)

---

## **2. Project Setup**

1. Initialize FastAPI project:

```bash
fastapi-app/
├── app/
│   ├── main.py
│   └── ...
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── .github/
    └── workflows/
        ├── ci.yml
        └── cd.yml
```

2. **Dockerfile** example:

```dockerfile
FROM python:3.10-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

3. **docker-compose.yml**:

```yaml
version: "3.8"

services:
  web:
    image: "${DOCKER_IMAGE}"
    restart: always
    ports:
      - "8000:8000"
    environment:
      ENV: production
```

---

## **3. GitHub Actions CI/CD**

### **CI Workflow (`ci.yml`)**

```yaml
name: CI - Test & Build

on:
  push:
    branches: ["main"]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: "3.10"

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run tests
        run: pytest
```

---

### **CD Workflow (`cd.yml`)**

```yaml
name: CD - Build, Push & Deploy

on:
  workflow_run:
    workflows: ["CI - Test & Build"]
    types: [completed]

jobs:
  deploy:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build & Push Docker Image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/fastapi-demo:latest
            ${{ secrets.DOCKERHUB_USERNAME }}/fastapi-demo:${{ github.sha }}

      - name: Deploy on EC2 via SSH
        env:
          DOCKER_IMAGE: ${{ secrets.DOCKERHUB_USERNAME }}/fastapi-demo:latest
          DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
          DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -H ${{ secrets.SSH_HOST }} >> ~/.ssh/known_hosts

          ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ${{ secrets.SSH_USER }}@${{ secrets.SSH_HOST }} bash -s << 'EOF'
            set -e

            APP_DIR="/home/ubuntu/app"
            mkdir -p "$APP_DIR"
            cd "$APP_DIR"

            # Overwrite deploy.sh
            cat > deploy.sh << 'DEPLOY_EOF'
#!/usr/bin/env bash
set -e

APP_DIR="/home/ubuntu/app"
cd "$APP_DIR"

: "${DOCKER_IMAGE:?Need to set DOCKER_IMAGE}"

# Login Docker Hub
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

# Pull latest image & restart container
docker-compose pull
docker-compose up -d --remove-orphans

# Cleanup old images
docker image prune -f

# Reload Nginx (Cloudflare Flexible SSL)
sudo systemctl reload nginx || true

echo "✅ Deployment successful: $DOCKER_IMAGE"
DEPLOY_EOF

            chmod +x deploy.sh
            ./deploy.sh
EOF
```

> **Secrets needed in GitHub:**
>
> - `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`
> - `SSH_HOST` → EC2 public IP
> - `SSH_USER` → usually `ubuntu`
> - `SSH_PRIVATE_KEY` → EC2 private key

---

## **4. EC2 Setup**

1. Install Docker & Docker Compose:

```bash
sudo apt update
sudo apt install docker.io docker-compose -y
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

2. Install Nginx:

```bash
sudo apt install nginx -y
sudo systemctl enable nginx
```

3. Configure firewall:

```bash
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

---

## **5. Nginx Configuration**

1. Create `/etc/nginx/sites-available/fastapi.conf`:

```nginx
server {
    listen 80;
    server_name mdrajib.xyz www.mdrajib.xyz;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

2. Enable site:

```bash
sudo ln -s /etc/nginx/sites-available/fastapi.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

3. Remove default config to avoid conflicts:

```bash
sudo rm /etc/nginx/sites-enabled/default
sudo systemctl reload nginx
```

---

## **6. Domain Setup (Namecheap + Cloudflare)**

1. **Namecheap DNS**: Point your A record to EC2 public IP.

2. **Cloudflare**:

   - Add domain to Cloudflare.
   - Set A record → **EC2 public IP**, proxy **orange cloud** (proxied).
   - SSL → **Flexible** (if no Certbot) or **Full Strict** (if Certbot is used).

3. Wait for DNS propagation (~5–10 mins).

---

## **7. Testing**

1. Check DNS resolution:

```bash
dig +short mdrajib.xyz
```

- Should resolve to Cloudflare IP (orange) or EC2 IP (gray).

2. Test FastAPI via Cloudflare:

```bash
curl -I https://mdrajib.xyz
curl -I http://mdrajib.xyz
```

3. Verify Docker container on EC2:

```bash
docker ps
docker logs <container_name>
```

4. Verify Nginx:

```bash
sudo systemctl status nginx
sudo nginx -t
```

---

## **8. CI/CD Flow**

1. Push code to GitHub → **CI runs tests**.
2. CI success → triggers CD workflow:

   - Builds Docker image
   - Pushes to Docker Hub
   - SSH into EC2 → deploys latest image via Docker Compose
   - Reloads Nginx if needed

Now your app updates automatically on every push. ✅

---

## **9. Optional: Full SSL via Certbot**

If you disable Cloudflare proxy (gray cloud), you can run:

```bash
sudo certbot --nginx -d mdrajib.xyz -d www.mdrajib.xyz
sudo systemctl reload nginx
```

- After issuance, you can re-enable Cloudflare orange cloud → set SSL mode to **Full (strict)**.

---

## **10. Summary**

- **CI/CD**: GitHub Actions → Docker Hub → EC2 deploy
- **Reverse proxy**: Nginx
- **SSL**: Cloudflare Flexible or Certbot Full SSL
- **Domain**: Namecheap → Cloudflare → EC2
- **Auto-deploy**: Push commit → pipeline handles everything

## **11. CI/CD + Deployment Workflow Diagram**

```text
        ┌─────────────┐
        │ Developer   │
        │ Push commit │
        └─────┬───────┘
              │
              ▼
        ┌─────────────┐
        │ GitHub      │
        │ Repository  │
        └─────┬───────┘
              │
              ▼
   ┌─────────────────────┐
   │ GitHub Actions CI   │
   │ - Checkout code     │
   │ - Install deps      │
   │ - Run tests         │
   └─────┬───────────────┘
         │ success
         ▼
   ┌─────────────────────┐
   │ GitHub Actions CD   │
   │ - Build Docker image│
   │ - Push to DockerHub │
   │ - SSH to EC2        │
   │ - Pull & deploy     │
   └─────┬───────────────┘
         │
         ▼
      ┌───────┐
      │ EC2   │
      │ Docker│
      │ Compose│
      │ Container│
      └───────┬─┘
              │
              ▼
        ┌─────────────┐
        │ Nginx       │
        │ Reverse     │
        │ Proxy       │
        └─────┬───────┘
              │
              ▼
        ┌─────────────┐
        │ Cloudflare  │
        │ SSL / CDN   │
        └─────┬───────┘
              │
              ▼
        ┌─────────────┐
        │ User Access │
        │ https://    │
        │ mdrajib.xyz │
        └─────────────┘
```

---

✅ This diagram shows **full automated flow**:

1. Developer pushes → CI runs tests.
2. CD builds Docker image, pushes to Docker Hub, SSH deploys on EC2.
3. EC2 runs Docker Compose container + Nginx reverse proxy.
4. Cloudflare handles SSL/CDN.
5. Users access app via domain.

---
