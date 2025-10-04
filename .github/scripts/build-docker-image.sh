#!/bin/bash
set -e

# Build and publish Docker image to Google Artifact Registry
# Usage: ./build-docker-image.sh <gar-location> <project-id> <repository> <image> <tag> <dockerfile> <directory> <arguments> [environment]

GAR_LOCATION=$1
PROJECT_ID=$2
REPOSITORY=$3
IMAGE=$4
TAG=$5
DOCKERFILE=$6
DIRECTORY=$7
ARGUMENTS=$8
ENVIRONMENT=${9:-"development"}

echo "Configuring Docker for GAR..."
gcloud --quiet auth configure-docker ${GAR_LOCATION}-docker.pkg.dev

echo "Building Docker image for environment: ${ENVIRONMENT}..."
cd ${DIRECTORY}

# Add environment suffix to tag for non-production environments
if [ "$ENVIRONMENT" = "production" ]; then
    ENV_TAG="${TAG}"
    echo "Creating production tag: ${ENV_TAG}"
else
    ENV_TAG="${TAG}-${ENVIRONMENT}"
    echo "Creating environment-specific tag: ${ENV_TAG}"
fi

# Add environment-specific labels
LABELS="--label environment=${ENVIRONMENT} --label build-date=$(date -u +'%Y-%m-%dT%H:%M:%SZ') --label version=${TAG}"

docker build \
    -t "${GAR_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE}:${ENV_TAG}" \
    ${LABELS} \
    ${ARGUMENTS} \
    -f ${DOCKERFILE} .

echo "Publishing Docker image..."
docker push "${GAR_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE}:${ENV_TAG}"

echo "Docker image build and publish completed successfully for ${ENVIRONMENT}!"
echo "Image tagged as: ${GAR_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE}:${ENV_TAG}"