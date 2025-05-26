#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME=local-docfactory:latest
K8_MANIFEST=k8-deployment.yaml

# 1) Ensure Docker is installed
if ! command -v docker &> /dev/null; then
  echo "🐳 Docker not found. Installing docker.io via apt..."
  sudo apt update
  sudo apt install -y docker.io
  echo "🔧 Enabling & starting Docker service..."
  sudo systemctl enable --now docker

  # add your user to 'docker' group so you can run without sudo
  echo "👤 Adding $USER to docker group (you will need to re-login)..."
  sudo usermod -aG docker "$USER"
  echo "✅ Docker installed. Please log out/in or restart your shell, then re-run this script."
  exit 0
else
  echo "🐳 Docker is already installed."
fi

# 2) Build the Docker image
echo "🔨 Building Docker image ${IMAGE_NAME}…"
docker build -t "${IMAGE_NAME}" .

# 3) Load into local cluster or push
if command -v kind &> /dev/null; then
  echo "🔄 Detected kind — loading image into kind cluster…"
  kind load docker-image "${IMAGE_NAME}"
elif command -v minikube &> /dev/null; then
  echo "🔄 Detected minikube — loading image into minikube…"
  minikube image load "${IMAGE_NAME}"
else
  echo "📤 No kind/minikube detected — pushing image to default registry…"
  docker push "${IMAGE_NAME}"
fi

# 4) Deploy to Kubernetes
echo "🚀 Applying Kubernetes manifest ${K8_MANIFEST}…"
kubectl apply -f "${K8_MANIFEST}"

echo "✅ Done! Your app is now running in Kubernetes."
