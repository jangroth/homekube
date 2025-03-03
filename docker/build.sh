#!/bin/bash -e

DOCKER_USERNAME="jangroth"
IMAGE_NAME="${DOCKER_USERNAME}/debug-utils"
IMAGE_TAG="1.0"

echo "${DOCKER_PAT}" | docker login -u ${DOCKER_USERNAME} --password-stdin

docker buildx build \
    --platform linux/arm64 \
    --tag ${IMAGE_NAME}:${IMAGE_TAG} \
    --file ./debug-utils/Dockerfile \
    --push \
    .
