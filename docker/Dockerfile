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
# Install debugging plugins
RUN git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git /root/.config/nvim/pack/plugins/start/plenary.nvim
RUN git clone --depth 1 https://github.com/jbyuki/one-small-step-for-vimkind.git /root/.config/nvim/pack/plugins/start/one-small-step-for-vimkind
RUN git clone --depth 1 https://github.com/mfussenegger/nvim-dap.git /root/.config/nvim/pack/plugins/start/nvim-dap
RUN git clone --depth 1 https://github.com/nvim-neotest/nvim-nio.git /root/.config/nvim/pack/plugins/start/nvim-nio
RUN git clone --depth 1 https://github.com/rcarriga/nvim-dap-ui.git /root/.config/nvim/pack/plugins/start/nvim-dap-ui
RUN git clone --depth 1 https://github.com/nvim-tree/nvim-web-devicons.git /root/.config/nvim/pack/plugins/start/nvim-web-devicons
# Create symlink to help with path mapping for debugger
RUN ln -s /plugin /host-plugin
VOLUME ["/plugin"]
CMD ["echo", "Please use run-tests.sh to execute tests"]
