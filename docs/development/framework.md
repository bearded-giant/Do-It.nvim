# Do-It.nvim Framework Architecture

## Overview

Do-It.nvim 2.0 introduces a modular framework that allows components to work independently or together. This architecture enables:

- Loading only the modules you need
- Using modules standalone or together
- Adding custom modules that integrate with the system
- Extending functionality without modifying core code

## Core Components

### 1. Module Registry

The module registry manages all loaded modules and provides:
- Dynamic module loading
- Dependency resolution
- Module lifecycle management
- Inter-module communication

### 2. Event System

The event system enables modules to communicate without direct dependencies:

```lua
-- Publishing an event
M.events.publish("todo:created", { todo = todo_data })

-- Subscribing to events
M.events.subscribe("todo:created", function(data)
    -- Handle the event
end)
```

### 3. Configuration Management

Centralized configuration handling with:
- Module-specific configurations
- Global settings
- Runtime configuration updates
- Validation and defaults

### 4. UI Framework

Common UI utilities for consistent interface design:
- Window management
- Buffer utilities
- Keybinding helpers
- Notification system

## Creating a Custom Module

### Module Structure

```lua
local M = {}

M.config = {
    -- Default configuration
}

function M.setup(config)
    -- Module initialization
    M.config = vim.tbl_deep_extend("force", M.config, config or {})
end

function M.load()
    -- Called when module is loaded by framework
end

function M.unload()
    -- Cleanup when module is unloaded
end

return M
```

### Registering with Framework

Modules are automatically discovered if placed in the correct directory structure:
```
lua/doit/modules/
└── mymodule/
    ├── init.lua      -- Main module file
    ├── config.lua    -- Configuration defaults
    └── ui.lua        -- UI components
```

### Module Metadata

```lua
M.metadata = {
    name = "mymodule",
    version = "1.0.0",
    description = "My custom module",
    author = "Your Name",
    dependencies = { "todos" },  -- Optional dependencies
}
```

## Best Practices

1. **Isolation**: Modules should be self-contained and not depend on internal implementation details of other modules
2. **Events**: Use the event system for loose coupling between modules
3. **Configuration**: Provide sensible defaults and validate user configuration
4. **Documentation**: Include help documentation and clear API documentation
5. **Testing**: Write tests for your module using the project's testing framework

## API Reference

See `:help doit-api` for the complete API reference.