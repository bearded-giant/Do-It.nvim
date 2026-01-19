# Codebase Structure

**Analysis Date:** 2026-01-19

## Directory Layout

```
do-it.nvim/
├── plugin/                 # Neovim plugin entry point
│   └── doit.vim           # VimL bootstrap
├── lua/doit/              # Main Lua source
│   ├── init.lua           # Plugin entry, module loading
│   ├── config.lua         # Global configuration
│   ├── core/              # Framework infrastructure
│   ├── modules/           # Feature modules (todos, notes, calendar)
│   ├── ui/                # Legacy/shared UI components
│   ├── state/             # Legacy state (compat shim)
│   ├── lualine.lua        # Statusline integration
│   ├── dashboard.lua      # Dashboard display
│   ├── calendar.lua       # Legacy calendar utilities
│   └── help.lua           # Help system
├── doc/                   # Vim help documentation
├── tests/                 # Test suites (plenary-based)
├── docker/                # Docker test environment
├── tmux/                  # Tmux integration scripts
└── docs/                  # Additional documentation
```

## Directory Purposes

**`plugin/`:**
- Purpose: Neovim plugin loader integration
- Contains: Single `doit.vim` file that bootstraps the Lua module
- Key files: `plugin/doit.vim`

**`lua/doit/`:**
- Purpose: Main plugin source code
- Contains: Entry point, config, integrations
- Key files: `init.lua`, `config.lua`, `lualine.lua`, `dashboard.lua`

**`lua/doit/core/`:**
- Purpose: Shared framework infrastructure
- Contains: Event system, registry, configuration, UI utilities, API
- Key files:
  - `init.lua`: Core framework setup, event system, module registration
  - `registry.lua`: Module tracking, dependencies, lifecycle
  - `config.lua`: Core configuration management
  - `api.lua`: Cross-module API utilities
  - `plugins.lua`: Plugin discovery
  - `ui/`: UI utilities (window.lua, modal.lua, theme.lua, multiline_input.lua)
  - `utils/`: Utility functions (fs.lua, path.lua, init.lua)

**`lua/doit/modules/`:**
- Purpose: Self-contained feature implementations
- Contains: Three main modules (todos, notes, calendar), plus obsidian-sync
- Structure per module:
  ```
  {module}/
  ├── init.lua       # Module entry, setup
  ├── config.lua     # Module-specific configuration
  ├── commands.lua   # Vim commands
  ├── state/         # State management
  │   ├── init.lua   # State aggregator
  │   ├── storage.lua# Persistence
  │   └── *.lua      # Domain operations
  └── ui/            # UI components
      ├── init.lua   # UI aggregator
      └── *_window.lua
  ```

**`lua/doit/ui/`:**
- Purpose: Legacy/shared UI components (primarily used by todos)
- Contains: Window implementations, actions, highlights
- Key files:
  - `main_window.lua`: Primary todo window (1143 lines, main UI)
  - `todo_actions.lua`: Todo CRUD operations
  - `highlights.lua`: Syntax highlighting setup
  - `list_selector.lua`: List selection modal
  - Other windows: help, tag, category, search, scratchpad, notes, list

**`lua/doit/state/`:**
- Purpose: Legacy state directory (compatibility shim location)
- Contains: Sub-modules that mirror todos state structure
- Note: `lua/doit/state.lua` is the actual compat shim

**`doc/`:**
- Purpose: Vim help documentation
- Contains: Help files for vimdoc `:help doit`
- Key files:
  - `doit.txt`: Main help file (18KB)
  - `doit_calendar.txt`: Calendar module help
  - `doit_framework.txt`: Framework/API documentation
  - `doit_linking.txt`: Note linking documentation
  - `tags`: Generated tags file

**`tests/`:**
- Purpose: Test suites using plenary.nvim
- Contains: Module tests, core tests, shared tests
- Structure:
  ```
  tests/
  ├── core/          # Core framework tests
  ├── modules/       # Per-module tests
  │   ├── todos/
  │   ├── notes/
  │   └── obsidian-sync/
  ├── shared/        # Shared functionality tests
  ├── legacy/        # Legacy API tests
  └── disabled_legacy/
  ```

**`docker/`:**
- Purpose: Isolated test environment
- Contains: Dockerfile, test configs, test runner scripts
- Key files: `run-tests.sh`, `init.lua`, `test-config.lua`

**`tmux/`:**
- Purpose: Tmux integration for external todo display
- Contains: Shell scripts for tmux status integration
- Key files: `do-it.tmux`

## Key File Locations

**Entry Points:**
- `plugin/doit.vim`: Neovim plugin loader entry
- `lua/doit/init.lua`: Main Lua entry, setup function

**Configuration:**
- `lua/doit/config.lua`: Global defaults and legacy config
- `lua/doit/core/config.lua`: Core framework config with migration
- `lua/doit/modules/*/config.lua`: Per-module configuration

**Core Logic:**
- `lua/doit/core/init.lua`: Framework setup, events, module registration
- `lua/doit/core/registry.lua`: Module lifecycle management
- `lua/doit/modules/todos/state/storage.lua`: Todo persistence (24KB, main storage logic)
- `lua/doit/modules/todos/state/todos.lua`: Todo CRUD operations

**Primary UI:**
- `lua/doit/ui/main_window.lua`: Main todo window (1143 lines)
- `lua/doit/modules/todos/ui/list_manager_window.lua`: List management (25KB)
- `lua/doit/modules/calendar/ui/day_view.lua`: Calendar day view

**Testing:**
- `tests/modules/todos/todos_spec.lua`: Todo module tests
- `tests/modules/notes/notes_spec.lua`: Notes module tests
- `tests/core/registry_spec.lua`: Registry tests

## Naming Conventions

**Files:**
- `init.lua`: Module entry point/aggregator
- `config.lua`: Configuration defaults
- `commands.lua`: Vim command definitions
- `*_window.lua`: UI window components
- `*_spec.lua`: Test files

**Directories:**
- `state/`: State management sub-modules
- `ui/`: UI components
- `modules/`: Feature modules
- `core/`: Framework infrastructure

**Lua Modules:**
- Pattern: `doit.{area}.{component}`
- Examples: `doit.core.registry`, `doit.modules.todos.state.storage`

## Where to Add New Code

**New Feature Module:**
- Create: `lua/doit/modules/{name}/`
- Required files: `init.lua`, `config.lua`
- Optional: `commands.lua`, `state/init.lua`, `ui/init.lua`
- Register in `lua/doit/init.lua` or via auto-discovery

**New Todo UI Component:**
- Implementation: `lua/doit/modules/todos/ui/{name}_window.lua`
- Register in: `lua/doit/modules/todos/ui/init.lua`
- Tests: `tests/modules/todos/{name}_spec.lua`

**New Core Utility:**
- Implementation: `lua/doit/core/utils/{name}.lua`
- Export from: `lua/doit/core/utils/init.lua`

**New State Operation (todos):**
- Implementation: `lua/doit/modules/todos/state/{domain}.lua`
- Export from: `lua/doit/modules/todos/state/init.lua`

**New Tests:**
- Module tests: `tests/modules/{module}/{feature}_spec.lua`
- Core tests: `tests/core/{feature}_spec.lua`
- Shared tests: `tests/shared/{feature}_spec.lua`

**New Vim Command:**
- Define in: `lua/doit/modules/{module}/commands.lua`
- Pattern: Return table from `setup(module)` with command definitions

## Special Directories

**`docker-data/`:**
- Purpose: Persistent data for docker test runs
- Generated: Yes
- Committed: No (in .gitignore)

**`.planning/`:**
- Purpose: GSD planning and analysis documents
- Generated: By analysis tools
- Committed: Optional

**`scratch/`:**
- Purpose: Workspace documentation and planning
- Generated: Manual/tool-assisted
- Committed: Optional

**`temp/`:**
- Purpose: Temporary files during development
- Generated: Yes
- Committed: No (empty dir)

**`.github/`:**
- Purpose: GitHub workflows and templates
- Generated: No
- Committed: Yes

---

*Structure analysis: 2026-01-19*
