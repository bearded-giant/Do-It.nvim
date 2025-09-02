# DoIt.nvim Modules

DoIt.nvim uses a modular architecture where each feature is implemented as a standalone module that integrates with the core framework.

## Available Modules

### Core Modules

- **[Todos](todos.md)** - Task management with priorities, due dates, and tags
- **[Notes](notes.md)** - Project-specific and global note-taking
- **[Calendar](calendar.md)** - Calendar view with icalbuddy integration

### Module Features

- **[Note Linking](NOTE_LINKING.md)** - Link notes to todos using wiki-style syntax

## Module Architecture

Each module follows a consistent structure:

```
lua/doit/modules/{module_name}/
├── init.lua           # Module entry point & API
├── config.lua         # Configuration management
├── state.lua          # State management
├── ui/                # User interface components
│   ├── init.lua
│   └── window.lua
└── commands.lua       # Vim commands
```

## Creating Custom Modules

Modules can be created as plugins that integrate with DoIt.nvim. Each module must:

1. Provide metadata for registration
2. Implement a `setup()` function
3. Register with the core framework
4. Define commands and keybindings

Example module structure:

```lua
local M = {}

M.version = "1.0.0"

M.metadata = {
    name = "my_module",
    version = M.version,
    description = "My custom module",
    author = "username",
    path = "doit.modules.my_module"
}

function M.setup(opts)
    -- Module initialization
    local core = require("doit.core")
    
    -- Setup configuration
    M.config = require("doit.modules.my_module.config").setup(opts)
    
    -- Initialize state
    M.state = require("doit.modules.my_module.state").setup(M)
    
    -- Initialize UI
    M.ui = require("doit.modules.my_module.ui").setup(M)
    
    -- Register with core
    core.register_module("my_module", M)
    
    return M
end

return M
```

## Module Configuration

Modules are configured in the `modules` section of the DoIt.nvim setup:

```lua
require("doit").setup({
    modules = {
        todos = {
            enabled = true,
            -- Todo-specific config
        },
        notes = {
            enabled = true,
            -- Notes-specific config
        },
        calendar = {
            enabled = true,
            -- Calendar-specific config
        }
    }
})
```

## Module Communication

Modules can interact with each other through:

- The core framework API
- Shared state management
- Event system (planned)
- Direct module references via `doit.modules.{name}`

## Future Modules

Planned modules include:

- **Habits** - Habit tracking and streaks
- **Pomodoro** - Time management with Pomodoro technique
- **Projects** - Project management and organization
- **Bookmarks** - Code and file bookmarking system