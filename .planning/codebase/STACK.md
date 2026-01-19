# Technology Stack

**Analysis Date:** 2026-01-19

## Languages

**Primary:**
- Lua 5.1+ - All plugin logic, state management, UI components

**Secondary:**
- Bash - Tmux integration scripts (`tmux/scripts/`)
- VimL - Plugin entry point (`plugin/doit.vim`)

## Runtime

**Environment:**
- Neovim >= 0.10.0
- Lua runtime embedded in Neovim (LuaJIT 2.1)

**Package Manager:**
- Lazy.nvim (recommended plugin manager for installation)
- No luarocks dependency for plugin itself
- Tests use plenary.nvim (installed via git in Docker)

## Frameworks

**Core:**
- Neovim Lua API (`vim.*`) - Window management, buffers, keymaps, user commands
- plenary.nvim - Testing framework (development dependency)

**Testing:**
- plenary.nvim test_harness - Test runner and assertions
- Docker - Containerized test environment

**Build/Dev:**
- Docker - Test environment with Alpine Linux base
- Make - Task runner for tests and docs (`Makefile`)

## Key Dependencies

**Critical (Runtime):**
- None - Pure Neovim plugin with no external Lua dependencies

**Development:**
- plenary.nvim - Testing (`/root/.config/nvim/pack/plugins/start/plenary.nvim`)
- oil.nvim - File navigation in Docker interactive mode

**Optional (Feature-specific):**
- icalbuddy (macOS CLI) - Calendar module integration
- lualine.nvim - Status line integration (`lua/doit/lualine.lua`)
- fzf - Tmux interactive todo management

## Configuration

**Environment:**
- No environment variables required
- Data stored in Neovim standard paths: `vim.fn.stdpath("data")` (typically `~/.local/share/nvim/`)

**Storage Paths:**
- Todos: `{stdpath}/doit/lists/{listname}.json`
- Notes: `{stdpath}/doit/notes/global.json` or `{stdpath}/doit/notes/project-{hash}.json`
- Session: `{stdpath}/doit/session.json`

**Build/Config Files:**
- `plugin/doit.vim` - VimL entry point, auto-loads on plugin startup
- `lua/doit/init.lua` - Main module entry, version 2.0.0
- `lua/doit/core/config.lua` - Default configuration with deep-merge support
- `Makefile` - Build tasks (test, check-docs, update-help, docker-interactive)

## Platform Requirements

**Development:**
- Docker for running tests
- macOS or Linux (test environment uses Alpine Linux)
- Neovim >= 0.10.0

**Production:**
- Neovim >= 0.10.0
- macOS required for calendar module (icalbuddy dependency)
- Cross-platform for todos and notes modules

## Module System

**Architecture:**
- Plugin framework with dynamic module loading
- Modules: `todos`, `notes`, `calendar`
- Entry points: `lua/doit/modules/{module}/init.lua`
- Standalone modules: `lua/doit_todos.lua`, `lua/doit_notes.lua`

**Module Loading:**
```lua
-- Full framework
require("doit").setup({ modules = { todos = { enabled = true } } })

-- Standalone
require("doit_todos").setup()
```

## Version

- Current: 2.0.0 (defined in `lua/doit/init.lua`)

---

*Stack analysis: 2026-01-19*
