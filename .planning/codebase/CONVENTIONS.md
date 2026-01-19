# Coding Conventions

**Analysis Date:** 2026-01-19

## Naming Patterns

**Files:**
- snake_case for all Lua files: `main_window.lua`, `due_dates.lua`, `three_day_view.lua`
- Spec files use `_spec.lua` suffix: `todos_spec.lua`, `modal_spec.lua`
- Init files for module entry points: `init.lua`

**Functions:**
- snake_case: `toggle_todo_window()`, `get_priority_score()`, `save_to_disk()`
- Boolean getters: `is_registered()`, `is_table()`
- Action verbs: `add_todo()`, `delete_todo()`, `toggle_todo()`, `edit_todo()`

**Variables:**
- snake_case: `current_index`, `active_filter`, `todo_count`
- Private/internal prefixed with underscore: `_score` (computed fields)
- Constants in UPPERCASE: `MAX_UNDO_HISTORY`

**Types/Tables:**
- Module tables: `M = {}` (single letter, uppercase)
- Configuration keys: snake_case in nested tables
- Metadata fields: snake_case: `config_schema`, `initialization_time`

## Code Style

**Formatting:**
- 4 spaces indentation (tabs converted to spaces)
- Line length: 120 characters max
- No trailing whitespace

**Linting:**
- No formal linter configured (no eslint/luacheck config found)
- Relies on manual review and test coverage

## Module Pattern

**Standard module structure:**
```lua
local M = {}

M.version = "2.0.0"

-- Module metadata for registry (optional for non-core modules)
M.metadata = {
    name = "module_name",
    version = M.version,
    description = "Description here",
    author = "author-name",
    path = "doit.modules.module_name",
    dependencies = {},
    config_schema = {}
}

-- Setup function receives options table
function M.setup(opts)
    local core = require("doit.core")

    -- 1. Initialize config
    local config = require("doit.modules.module_name.config")
    M.config = config.setup(opts)

    -- 2. Initialize state
    local state_module = require("doit.modules.module_name.state")
    M.state = state_module.setup(M)

    -- 3. Initialize UI
    local ui_module = require("doit.modules.module_name.ui")
    M.ui = ui_module.setup(M)

    -- 4. Initialize commands
    M.commands = require("doit.modules.module_name.commands").setup(M)

    -- 5. Register with core
    core.register_module("module_name", M)

    -- 6. Setup keymaps
    M.setup_keymaps()

    return M
end

return M
```

**Standalone module support:**
```lua
-- For modules that can work without the full framework
function M.standalone_setup(opts)
    if not package.loaded["doit.core"] then
        local minimal_core = {
            register_module = function() return end,
            get_module = function() return nil end,
            events = {
                on = function() return function() end end,
                emit = function() return end
            }
        }
        package.loaded["doit.core"] = minimal_core
    end

    return M.setup(opts)
end
```

## Import Organization

**Order:**
1. Local vim references (if needed): `local vim = vim`
2. Core framework modules: `local core = require("doit.core")`
3. Module-specific dependencies: `local config = require("doit.modules.todos.config")`
4. Local variable declarations

**Path Aliases:**
- No path aliases configured
- Use full require paths: `require("doit.modules.todos.state.sorting")`

**Example:**
```lua
local vim = vim
local api = vim.api

local M = {}

local ns_id = vim.api.nvim_create_namespace("doit")
local highlight_cache = {}
```

## Error Handling

**Notification Pattern:**
```lua
vim.notify("DoIt Calendar: icalbuddy not found", vim.log.levels.WARN)
vim.notify("Todo module not available", vim.log.levels.ERROR)
```

**Log levels used:**
- `vim.log.levels.INFO` - Informational messages
- `vim.log.levels.WARN` - Warnings (missing dependencies, etc.)
- `vim.log.levels.ERROR` - Errors requiring user attention

**Protected calls for external operations:**
```lua
local success, result = pcall(require, module_path)
if not success or not module then
    return nil, "Failed to load module: " .. tostring(module)
end
```

**Return pattern for operations:**
```lua
function M.set_due_date(index, date_string)
    if not state.todos[index] then
        return false, "Todo index out of range"
    end
    -- ... operation ...
    return true, "Due date set to " .. date_string
end
```

## Validation

**Early parameter validation:**
```lua
function M.register(name, info)
    if not name or type(name) ~= "string" then
        error("Module name must be a string")
    end
    -- ... rest of function
end
```

**Index bounds checking:**
```lua
if not state.todos[index] then
    return false, "Todo index out of range"
end
```

**Type checking utilities:**
```lua
M.is_table = function(t) return type(t) == "table" end
M.is_string = function(s) return type(s) == "string" end
M.is_function = function(f) return type(f) == "function" end
M.is_nil = function(n) return n == nil end
```

## UI Patterns

**Window creation:**
```lua
local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Title ",
    title_pos = "center"
})
```

**Buffer options:**
```lua
vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
vim.api.nvim_buf_set_option(buf, "modifiable", true)
-- ... set lines ...
vim.api.nvim_buf_set_option(buf, "modifiable", false)
```

**Keymap setup:**
```lua
vim.api.nvim_buf_set_keymap(buf, "n", key, "", {
    nowait = true,
    noremap = true,
    silent = true,
    callback = callback
})
```

**Highlight groups:**
```lua
vim.api.nvim_set_hl(0, "DoItPending", { link = "Question", default = true })
vim.api.nvim_set_hl(0, "DoItDone", { link = "Comment", default = true })
```

## State Management

**State initialization pattern:**
```lua
function M.setup(state)
    function M.add_todo(text, priorities)
        -- operates on shared state
        table.insert(state.todos, new_todo)
        state.save_todos()
        return new_todo
    end

    return M
end
```

**Save after mutation:**
```lua
function M.toggle_todo(index)
    if state.todos[index] then
        local todo = state.todos[index]
        -- ... modify todo ...
        state.save_todos()  -- always save after state change
    end
end
```

## Event System

**Event subscription:**
```lua
local unsubscribe = core.events.on("note_updated", function(data)
    if data and data.id then
        -- handle event
    end
end)
```

**Event emission:**
```lua
core.events.emit("todos_updated", {
    reason = "note_linked",
    todo_id = todo_id,
    note_id = data.id
})
```

## Data Structures

**Todo item structure:**
```lua
{
    id = "timestamp_randomnumber",  -- e.g., "1737312000_1234567"
    text = "Todo text here",
    done = false,
    in_progress = false,
    timestamp = os.time(),
    order_index = 1,
    priorities = { "urgent" },  -- optional
    due_date = "2025-01-20",    -- optional, YYYY-MM-DD format
    note_id = "note_123",       -- optional, linked note
    note_summary = "Summary",   -- optional
    note_updated_at = 1737312000  -- optional
}
```

**Module metadata structure:**
```lua
{
    name = "module_name",
    version = "1.0.0",
    path = "doit.modules.module_name",
    description = "Module description",
    author = "author-name",
    dependencies = {},
    config_schema = {
        enabled = { type = "boolean", default = true },
        window = { type = "table" }
    }
}
```

## Comments

**When to Comment:**
- Module purpose at top of file (optional)
- Complex sorting/filtering logic
- Non-obvious algorithm choices

**JSDoc/TSDoc:**
- Not used (Lua codebase)

**Comment style:**
- Single line: `-- comment text`
- All lowercase for inline comments

---

*Convention analysis: 2026-01-19*
