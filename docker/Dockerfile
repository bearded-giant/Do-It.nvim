FROM alpine:latest
RUN apk add --no-cache \
    neovim \
    git \
    lua5.3 \
    luarocks
RUN mkdir -p /root/.config/nvim/pack/plugins/start
# Create data directory for doit plugin to write to
RUN mkdir -p /data && chmod 777 /data
WORKDIR /plugin
COPY ./init.lua /root/.config/nvim/init.lua
RUN git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git /root/.config/nvim/pack/plugins/start/plenary.nvim
VOLUME ["/plugin"]
CMD ["echo", "Please use run-tests.sh to execute tests"]
