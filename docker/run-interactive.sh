#!/bin/bash

# Change to the docker directory
cd "$(dirname "$0")"

# Build the Docker image if needed
docker build -t dooing-plugin-interactive .

# Run interactive Neovim session with the plugin mounted
docker run --rm -it -v "$(pwd)/..:/plugin" dooing-plugin-interactive nvim
