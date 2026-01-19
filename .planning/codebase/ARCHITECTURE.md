# Architecture

**Analysis Date:** 2026-01-19

## Pattern Overview

**Overall:** Modular Plugin Architecture with Event-Driven Communication

**Key Characteristics:**
- Plugin-style framework where core provides infrastructure (events, registry, UI utilities)
- Feature modules (todos, notes, calendar) are self-contained with their own config/state/UI/commands
- Cross-module communication via publish-subscribe event system
- Backwards compatibility layer for legacy single-file API

## Layers

**Plugin Entry (`plugin/doit.vim`):**
- Purpose: Neovim plugin bootstrap
- Location: `plugin/doit.vim`
- Contains: Vim script guard, auto-loads doit module
- Depends on: `lua/doit/init.lua`
- Used by: Neovim plugin loader

**Main Entry (`lua/doit/init.lua`):**
- Purpose: Plugin initialization, module loading, backwards compatibility
- Location: `lua/doit/init.lua`
- Contains: `setup()`, `load_module()`, command registration, legacy API exposure
- Depends on: `doit.core`, `doit.config`, `doit.modules.*`
- Used by: User setup, plugin entry

**Core Framework (`lua/doit/core/`):**
- Purpose: Shared infrastructure for all modules
- Location: `lua/doit/core/`
- Contains: Event system, module registry, configuration management, UI utilities, API
- Depends on: Neovim APIs
- Used by: All feature modules

**Feature Modules (`lua/doit/modules/`):**
- Purpose: Self-contained feature implementations
- Location: `lua/doit/modules/{module_name}/`
- Contains: Each module has: init.lua, config.lua, commands.lua, state/, ui/
- Depends on: Core framework, optionally other modules via events
- Used by: Main init via load_module()

**Legacy UI Layer (`lua/doit/ui/`):**
- Purpose: Original monolithic UI components (still used by todos module)
- Location: `lua/doit/ui/`
- Contains: Window implementations, todo_actions, highlights
- Depends on: `doit.config`, `doit.state`, `doit.core`
- Used by: Todos module, backwards compatibility

**Compatibility Shims:**
- `lua/doit/state.lua`: Forwards to `modules/todos/state`
- `lua/doit/calendar.lua`: Legacy calendar utilities

## Data Flow

**Plugin Initialization:**

1. User calls `require("doit").setup(opts)` in their Neovim config
2. Global config merged via `doit.config.setup(opts)`
3. Core framework initialized via `doit.core.setup(opts)` - sets up events, registry, UI
4. Plugin discovery runs if enabled (`plugins.auto_discover`)
5. Modules loaded via `load_module(name, opts)` - each gets registered, setup called
6. Legacy API exposed at root level for backwards compatibility

**Module Initialization (e.g., todos):**

1. `modules/todos/init.lua:setup(opts)` called
2. Module-specific config merged: `modules/todos/config.lua`
3. State initialized: `modules/todos/state/init.lua` loads sub-modules (storage, todos, priorities, etc.)
4. UI initialized: `modules/todos/ui/init.lua` loads window components
5. Commands registered: `modules/todos/commands.lua`
6. Module registered with core: `core.register_module("todos", M)`
7. Event listeners attached for cross-module communication

**User Interaction (Toggle Todo Window):**

1. User triggers `:DoIt` or keymap
2. Command calls `M.ui.main_window.toggle_todo_window()`
3. Window creates buffer, loads current state via `ensure_state_loaded()`
4. `render_todos()` formats and displays todos with highlights
5. Keymaps bound to buffer call `todo_actions.*` functions
6. State mutations call `state.save_todos()` which persists to JSON
7. Core events emitted for other modules to react

**State Management:**
- Each module maintains isolated state in `modules/{name}/state/`
- State persisted to JSON files (todos: `~/.local/share/nvim/doit/lists/*.json`)
- State loaded lazily on first access, reloaded on file changes (lualine monitors mtime)

## Key Abstractions

**Module:**
- Purpose: Self-contained feature unit with standardized interface
- Examples: `lua/doit/modules/todos/init.lua`, `lua/doit/modules/notes/init.lua`, `lua/doit/modules/calendar/init.lua`
- Pattern: Each exports `M.setup(opts)` returning module table with `state`, `ui`, `commands`, `config`
- Metadata: `M.metadata` defines name, version, description, dependencies, config_schema

**Core Registry (`lua/doit/core/registry.lua`):**
- Purpose: Module registration, dependency checking, initialization
- Pattern: Tracks modules by name, validates configs, manages lifecycle
- Key functions: `register()`, `is_registered()`, `initialize_module()`, `check_dependencies()`

**Event System (`lua/doit/core/init.lua:M.events`):**
- Purpose: Decoupled cross-module communication
- Pattern: Pub-sub with `on(event, callback)` and `emit(event, data)`
- Events: `note_created`, `note_updated`, `note_deleted`, `todos_updated`

**Core UI (`lua/doit/core/ui/`):**
- Purpose: Reusable UI primitives
- Components:
  - `window.lua`: Float window creation, positioning, buffer management
  - `modal.lua`: List/selection modal with preview panel
  - `theme.lua`: Theme utilities
  - `multiline_input.lua`: Multi-line text input

**State Module Pattern:**
- Purpose: Isolated state management per feature
- Structure: `modules/{name}/state/init.lua` aggregates sub-modules
- Sub-modules: storage.lua (persistence), domain-specific operations (todos.lua, priorities.lua, etc.)
- Each sub-module exports functions that get merged into parent state via setup()

## Entry Points

**User Setup:**
- Location: `lua/doit/init.lua:M.setup(opts)`
- Triggers: User's init.lua/lazy config
- Responsibilities: Config merge, core init, module loading

**Plugin Commands:**
- Location: Registered via `core.register_module()` or `init.lua:register_module_commands()`
- Examples: `:DoIt`, `:DoItNotes`, `:DoItCalendar`, `:DoItPlugins`

**Keymaps:**
- Global: Registered in module `setup_keymaps()` functions
- Buffer-local: Set in window creation functions (e.g., `main_window.lua:create_window()`)

**Lualine Integration:**
- Location: `lua/doit/lualine.lua`
- Functions: `active_todo()`, `current_list()`, `todo_stats()`
- Pattern: Polls state on each statusline render, monitors file mtime for external changes

## Error Handling

**Strategy:** Defensive with pcall, graceful degradation, user notifications

**Patterns:**
- `pcall(require, "module")` for optional dependencies
- `vim.notify()` with appropriate log levels for user feedback
- Fallback implementations when modules unavailable
- State validation before operations

## Cross-Cutting Concerns

**Logging:** `vim.notify()` with levels (INFO, WARN, ERROR)

**Validation:**
- Config schema validation in registry
- Early parameter validation in state functions
- Cursor position bounds checking in UI

**Authentication:** Not applicable (local-only plugin)

**Configuration:**
- Global: `lua/doit/config.lua` - merged defaults with user opts
- Per-module: `lua/doit/modules/{name}/config.lua`
- Legacy migration: `core/config.lua:migrate_legacy_config()`

---

*Architecture analysis: 2026-01-19*
