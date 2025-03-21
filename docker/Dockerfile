FROM alpine:latest

# Install necessary packages
RUN apk add --no-cache \
    neovim \
    git \
    lua5.3 \
    luarocks

# Create plugin directories
RUN mkdir -p /root/.config/nvim/pack/plugins/start

# Create directory for the plugin
WORKDIR /plugin

# Copy minimal init.lua for testing
COPY ./init.lua /root/.config/nvim/init.lua

# Install plenary.nvim for testing
RUN git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git /root/.config/nvim/pack/plugins/start/plenary.nvim

# Mount point for your plugin code will be /plugin
VOLUME ["/plugin"]

# Default command to run tests
CMD ["nvim", "--headless", "-c", "lua require('plenary.test_harness').test_directory('tests')", "-c", "qa!"]
