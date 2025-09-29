# DoIt.nvim Plugin Development Guide

This guide covers everything you need to know to create a new plugin/module for DoIt.nvim.

## Quick Start

The fastest way to create a new module is to follow this template:

```lua
-- lua/doit/modules/mymodule/init.lua
local M = {}

-- Module version
M.version = "1.0.0"

-- Module metadata for registry
M.metadata = {
    name = "mymodule",
    version = M.version,
    description = "Brief description of what your module does",
    author = "Your Name",
    path = "doit.modules.mymodule",
    dependencies = {},  -- List other modules you depend on
    config_schema = {
        enabled = { type = "boolean", default = true },
        -- Add your configuration options here
    }
}

-- Setup function called when module is loaded
function M.setup(opts)
    local core = require("doit.core")

    -- Setup configuration
    local config = require("doit.modules.mymodule.config")
    M.config = config.setup(opts)

    -- Initialize your module components
    -- M.state = require("doit.modules.mymodule.state").setup(M)
    -- M.ui = require("doit.modules.mymodule.ui").setup(M)
    -- M.commands = require("doit.modules.mymodule.commands").setup(M)

    return M
end

return M
```

## Module Structure

A complete module typically has this structure:

```
lua/doit/modules/mymodule/
├── init.lua         # Main module entry point
├── config.lua       # Configuration management
├── commands.lua     # Vim commands
├── state.lua        # State management
├── ui/              # UI components
│   ├── init.lua     # UI coordinator
│   └── window.lua   # Window management
└── README.md        # Module documentation
```

## Core Components

### 1. Configuration (config.lua)

```lua
local M = {}

M.defaults = {
    enabled = true,
    window = {
        position = "right",
        width = 80,
        height = 30
    },
    keymaps = {
        close = "q",
        submit = "<CR>"
    }
}

function M.setup(opts)
    return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
```

### 2. Commands (commands.lua)

```lua
local M = {}
local module = nil

function M.setup(parent_module)
    module = parent_module

    vim.api.nvim_create_user_command("DoItMyModule", function(opts)
        local args = vim.split(opts.args or "", " ")
        local cmd = args[1] or "toggle"

        if cmd == "toggle" then
            module.toggle()
        elseif cmd == "show" then
            module.show()
        elseif cmd == "hide" then
            module.hide()
        end
    end, {
        nargs = "*",
        desc = "MyModule commands"
    })

    return M
end

return M
```

### 3. State Management (state.lua)

```lua
local M = {}
local state = {
    is_open = false,
    data = {}
}

function M.setup(module)
    return M
end

function M.is_open()
    return state.is_open
end

function M.set_open(value)
    state.is_open = value
end

function M.get_data()
    return state.data
end

function M.set_data(data)
    state.data = data
end

return M
```

### 4. UI Components (ui/init.lua)

```lua
local M = {}
local module = nil
local window = nil

function M.setup(parent_module)
    module = parent_module
    window = require("doit.modules.mymodule.ui.window").setup(parent_module)
    return M
end

function M.show()
    if not window then return end
    window.create()
    M.refresh()
end

function M.hide()
    if not window then return end
    window.close()
end

function M.refresh()
    -- Update UI content
    local lines = M.render()
    window.set_content(lines)
end

function M.render()
    local lines = {}
    -- Generate content lines
    return lines
end

return M
```

## Best Practices

### 1. Module Independence

- Modules should be self-contained
- Use events for communication between modules
- Don't rely on internal implementation details of other modules

### 2. Error Handling

```lua
-- Good: Graceful degradation
if not vim.fn.executable("required-tool") then
    vim.notify("Module requires 'required-tool' to be installed", vim.log.levels.WARN)
    return M
end

-- Good: Validate configuration
if type(opts.setting) ~= "string" then
    vim.notify("Invalid configuration: setting must be a string", vim.log.levels.ERROR)
    opts.setting = M.defaults.setting
end
```

### 3. Documentation

Every module should include:

1. **README.md** in the module directory
2. **Help documentation** in doc/
3. **Clear comments** in code
4. **Type annotations** where helpful

### 4. Testing

Create tests in `tests/modules/mymodule_spec.lua`:

```lua
describe("mymodule", function()
    it("should initialize correctly", function()
        local module = require("doit.modules.mymodule")
        module.setup({})
        assert.is_not_nil(module.config)
    end)
end)
```

## Event System

Use events for loose coupling:

```lua
-- Publishing events
local core = require("doit.core")
core.events.publish("mymodule:action", { data = value })

-- Subscribing to events
core.events.subscribe("todos:created", function(event_data)
    -- React to todos being created
end)
```

## Common Patterns

### 1. Lazy Loading

```lua
-- Only load heavy dependencies when needed
function M.show()
    if not M.ui then
        M.ui = require("doit.modules.mymodule.ui").setup(M)
    end
    M.ui.show()
end
```

### 2. Caching

```lua
local cache = {}
local cache_timeout = 300  -- seconds

function M.get_data()
    local now = os.time()
    if cache.data and cache.time and (now - cache.time) < cache_timeout then
        return cache.data
    end

    cache.data = M.fetch_data()
    cache.time = now
    return cache.data
end

function M.clear_cache()
    cache = {}
end
```

### 3. Keybindings

```lua
function M.setup_keymaps()
    local buf = window.get_buffer()
    local opts = { buffer = buf, silent = true }

    for action, key in pairs(module.config.keymaps) do
        if key then
            vim.keymap.set("n", key, function()
                M.handle_action(action)
            end, opts)
        end
    end
end
```

## Integration Points

### 1. Main Menu

To add your module to the main DoIt dashboard:

```lua
-- In your module's setup
core.dashboard.register({
    name = "mymodule",
    icon = "🔧",
    description = "My Module",
    command = "DoItMyModule"
})
```

### 2. Status Line

Provide status line integration:

```lua
function M.statusline()
    if not M.state.is_open() then
        return ""
    end
    return string.format("MyModule: %d items", #M.state.get_data())
end
```

### 3. File Types

Register custom filetypes:

```lua
vim.filetype.add({
    extension = {
        mymod = "mymodule"
    }
})
```

## Example: Calendar Module v2.0

The Calendar module (v2.0) is a good example of a complete module:

- **Parser**: Complex icalbuddy output parsing
- **UI**: Multiple view modes (day, 3-day, week)
- **State**: Event caching and date management
- **Commands**: Rich command set with diagnostics
- **Configuration**: Extensive customization options

See `/lua/doit/modules/calendar/` for the implementation.

## Checklist for New Modules

- [ ] Module follows the standard structure
- [ ] Has proper metadata with version
- [ ] Includes comprehensive README.md
- [ ] Handles errors gracefully
- [ ] Uses events for inter-module communication
- [ ] Has unit tests
- [ ] Includes vim help documentation
- [ ] Follows Lua style guidelines
- [ ] Properly cleans up on unload
- [ ] Configuration has sensible defaults

## Getting Help

- Check existing modules for examples
- Review the test suite for patterns
- Open an issue for architectural questions
- Submit a draft PR for early feedback

## Contributing

When your module is ready:

1. Ensure all tests pass: `docker/run-tests.sh`
2. Update main README if it's a core module
3. Add documentation to `docs/modules/`
4. Submit a pull request with a clear description

Remember: Good modules are focused, well-documented, and play nicely with the rest of the ecosystem.