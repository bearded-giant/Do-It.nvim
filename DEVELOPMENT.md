# Do-It.nvim Development Guide

This document explains how to set up a development environment and use debugging tools for Do-It.nvim.

## Enabling Development Mode

Development mode provides access to additional commands and features useful for plugin development:

1. Add `development_mode = true` to your plugin configuration:

```lua
require('doit').setup({
  development_mode = true,
  -- Your other configuration options...
})
```

## Development Commands

When development mode is enabled, the following commands become available:

| Command | Description |
|---------|-------------|
| `:DoitReload` | Reload the Do-It.nvim plugin |
| `:DoitAutoReload` | Toggle automatic plugin reloading when source files change |
| `:DoitDebug` | Start a Lua debug server for the plugin (requires OSV) |
| `:DoitDebugConnect` | Start debug server and connect DAP |
| `:DoitDebugStatus` | Check DAP connection status |

## Debugging with DAP and OSV

The plugin supports debugging with [nvim-dap](https://github.com/mfussenegger/nvim-dap) and [one-small-step-for-vimkind](https://github.com/jbyuki/one-small-step-for-vimkind) (OSV).

### Setup

1. Install the required plugins:

   ```lua
   use('mfussenegger/nvim-dap')             -- Debug Adapter Protocol client
   use('jbyuki/one-small-step-for-vimkind') -- Lua debugger for Neovim
   use('rcarriga/nvim-dap-ui')              -- UI for DAP (optional but recommended)
   ```

2. Configure DAP for Lua debugging in your Neovim config:

   ```lua
   local dap = require('dap')
   
   -- Configure nlua adapter
   dap.adapters.nlua = function(callback, config)
     callback({
       type = 'server',
       host = config.host or "127.0.0.1",
       port = config.port or 8086
     })
   end
   
   -- Configure Lua configuration
   dap.configurations.lua = {
     {
       type = 'nlua',
       request = 'attach',
       name = "Attach to running Neovim instance",
       host = "127.0.0.1",
       port = 8086,
     }
   }
   ```

### Debugging Workflow

1. Enable development mode in your Do-It.nvim config.

2. Start a debugging session:
   - Option 1: Run `:DoitDebugConnect` command
   - Option 2: Use the `<leader>osc` keybinding
   - Option 3: Run `:DoitDebug` and then connect with DAP manually

3. Set breakpoints in the plugin code:
   - Use `:lua require('dap').toggle_breakpoint()` or your DAP keybinding

4. Trigger the code you want to debug, and execution will stop at your breakpoints.

### Handling Neovim Freezes

If Neovim becomes unresponsive during debugging, you might want to set up an emergency exit keybinding in your DAP configuration:

```lua
vim.api.nvim_set_keymap("n", "<leader>dq", "<cmd>lua require('dap').terminate()<CR>", 
                        {noremap = true, silent = true, desc = "Emergency DAP Exit"})
```

## Development Tips

### Auto-reloading

For iterative development, enable auto-reload by running `:DoitAutoReload`. The plugin will reload automatically whenever you save changes to any of its files.

### Plugin Structure

- `lua/doit/init.lua` - Main entry point
- `lua/doit/config.lua` - Configuration handling
- `lua/doit/state/` - Todo data management
- `lua/doit/ui/` - User interface components
- `lua/doit/development.lua` - Development utilities (only loaded when development_mode=true)

### Docker Development Environment

The plugin includes Docker support for consistent development and testing. In the `docker/` directory you'll find:

- `run-tests.sh` - Script to run the test suite in a Docker container:

  ```bash
  ./docker/run-tests.sh
  ```

- `run-interactive.sh` - Script to start an interactive Neovim session with the plugin loaded:

  ```bash
  ./docker/run-interactive.sh
  ```

The interactive script:

- Builds a Docker image for the plugin
- Creates a data directory at `~/.doit-data` for persistent storage
- Mounts your plugin directory into the container
- Loads your personal plugin configuration from dotfiles

This provides a consistent and isolated environment for testing and development.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Enable development mode for better workflow
4. Make your changes
5. Run tests to ensure everything works
6. Submit a pull request

---

Remember: Development tools are only available when `development_mode` is set to `true`. This keeps the plugin lightweight for regular users while giving developers the tools they need.

