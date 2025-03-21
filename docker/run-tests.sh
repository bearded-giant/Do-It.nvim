#!/bin/bash

# Change to the docker directory
cd "$(dirname "$0")"

# Build the Docker image
docker build -t dooing-plugin-test .

# Run automated tests
docker run --rm -v "$(pwd)/..:/plugin" dooing-plugin-test

# For interactive testing, uncomment:
# docker run --rm -it -v "$(pwd)/..:/plugin" dooing-plugin-test nvim
