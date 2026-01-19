# Testing Patterns

**Analysis Date:** 2026-01-19

## Test Framework

**Runner:**
- Plenary.nvim test harness
- Config: No explicit config file (uses plenary defaults)

**Assertion Library:**
- luassert (bundled with plenary)

**Run Commands:**
```bash
# Run all tests (Docker - recommended)
docker/run-tests.sh

# Run tests with pattern
docker/run-tests.sh --pattern "todos_spec"

# Run tests in specific directory
docker/run-tests.sh --dir "tests/modules/todos"

# Run all tests (native, if plenary installed)
nvim --headless -c "lua require('plenary.test_harness').test_directory('tests')" -c "qa!"

# Run specific module tests
nvim --headless -c "lua require('plenary.test_harness').test_directory('tests/modules/todos')" -c "qa!"

# Run single test file pattern
nvim --headless -c "lua require('plenary.test_harness').test_directory('tests', {pattern = 'todos_spec'})" -c "qa!"
```

## Test File Organization

**Location:**
- Tests in `tests/` directory (separate from source)
- Mirrors source structure under `tests/`

**Naming:**
- `*_spec.lua` suffix for all test files
- Named after module being tested: `todos_spec.lua`, `modal_spec.lua`

**Structure:**
```
tests/
├── TESTING.md                    # Test documentation
├── README.md                     # Test output explanation
├── core/                         # Core framework tests
│   ├── framework_spec.lua
│   ├── registry_spec.lua
│   └── ui/
│       └── modal_spec.lua
├── modules/                      # Module-specific tests
│   ├── todos/
│   │   ├── todos_spec.lua
│   │   ├── state_spec.lua
│   │   ├── linking_spec.lua
│   │   └── todo_actions_spec.lua
│   ├── notes/
│   │   ├── notes_spec.lua
│   │   ├── linking_spec.lua
│   │   └── ui_spec.lua
│   └── calendar_spec.lua
├── shared/                       # Cross-module utilities
│   ├── storage_spec.lua
│   ├── tags_spec.lua
│   ├── reordering_spec.lua
│   └── ui_reordering_spec.lua
├── legacy/                       # Old tests being migrated
│   └── doit_spec.lua
└── disabled_legacy/              # Disabled tests (.disabled extension)
```

## Test Structure

**Suite Organization:**
```lua
describe("module_name", function()
    local module_under_test

    before_each(function()
        -- Clear module cache to ensure clean state
        package.loaded["doit.modules.module_name"] = nil
        package.loaded["doit.modules.module_name.config"] = nil
        package.loaded["doit.modules.module_name.state"] = nil

        -- Set up mocks (detailed below)
        package.loaded["doit.core"] = {
            register_module = function(_, module) return module end,
            get_module = function() return nil end,
            events = {
                on = function() return function() end end,
                emit = function() return end
            }
        }

        -- Load module under test
        module_under_test = require("doit.modules.module_name")
    end)

    after_each(function()
        -- Clean up resources
    end)

    it("should do something specific", function()
        -- Arrange
        local input = "test input"

        -- Act
        local result = module_under_test.some_function(input)

        -- Assert
        assert.are.equal("expected", result)
    end)
end)
```

**Nested describe blocks:**
```lua
describe("todos linking", function()
    describe("process_note_links", function()
        it("should extract note links from todo text", function()
            -- test implementation
        end)

        it("should handle todos with no links", function()
            -- test implementation
        end)
    end)

    describe("add_todo", function()
        it("should process links when adding a new todo", function()
            -- test implementation
        end)
    end)
end)
```

## Mocking

**Framework:** Manual mocking via `package.loaded`

**Core module mock pattern:**
```lua
package.loaded["doit.core"] = {
    register_module = function(_, module) return module end,
    get_module = function(name)
        if name == "notes" then
            return package.loaded["doit.modules.notes"]
        end
        return nil
    end,
    get_module_config = function() return {
        save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
        priorities = {}
    } end,
    events = {
        on = function() return function() end end,
        emit = function() return end
    },
    config = {
        modules = {
            todos = { save_path = "/tmp/test.json" }
        }
    }
}
```

**State mock pattern:**
```lua
local mock_state = {
    todos = {},
    active_filter = nil,
    deleted_todos = {},
    MAX_UNDO_HISTORY = 50,
    delete_todo = function(index)
        local todo = mock_state.todos[index]
        if todo then
            table.insert(mock_state.deleted_todos, 1, todo)
            table.remove(mock_state.todos, index)
        end
    end,
    save_to_disk = function() end,
    load_from_disk = function() end
}
```

**Vim API mock pattern:**
```lua
local mock_buf_id = 1
local mock_win_id = 100

vim.api.nvim_win_is_valid = function(win) return win == mock_win_id end
vim.api.nvim_buf_is_valid = function(buf) return buf == mock_buf_id end
vim.api.nvim_win_get_buf = function() return mock_buf_id end
vim.api.nvim_win_get_cursor = function() return { 2, 0 } end
vim.api.nvim_buf_get_lines = function(buf, start, end_, strict)
    return { "", "  ○ Test todo", "" }
end
vim.notify = function() end
vim.schedule = function(fn) fn() end
```

**Using luassert stubs:**
```lua
local stub = require("luassert.stub")

before_each(function()
    stub(state, "save_to_disk")
end)

after_each(function()
    state.save_to_disk:revert()
end)

it("should call save", function()
    -- ... test code ...
    assert.stub(state.save_to_disk).was.called(1)
end)
```

**What to Mock:**
- Core framework (`doit.core`)
- vim.api functions for UI tests
- File I/O (`io.open`)
- External dependencies
- Module dependencies when testing in isolation

**What NOT to Mock:**
- The module under test itself
- Core business logic being verified
- vim standard library functions (vim.tbl_deep_extend, etc.)

## Fixtures and Factories

**Test Data:**
```lua
before_each(function()
    mock_state.todos = {
        { id = "1", text = "Todo with #tag1", done = false, in_progress = false },
        { id = "2", text = "Todo with #tag2 and #tag3", done = false, in_progress = false },
        { id = "3", text = "Another #tag1 todo", done = true, in_progress = false },
    }
end)
```

**Todo factory pattern (inline):**
```lua
local function create_todo(overrides)
    return vim.tbl_extend("force", {
        id = tostring(math.random(1000000)),
        text = "Test todo",
        done = false,
        in_progress = false,
        timestamp = os.time(),
        order_index = 1
    }, overrides or {})
end

-- Usage
mock_state.todos = {
    create_todo({ text = "First", order_index = 1 }),
    create_todo({ text = "Second", order_index = 2 }),
}
```

**Location:**
- No separate fixtures directory
- Test data created inline in `before_each` blocks

## Coverage

**Requirements:** None enforced

**View Coverage:**
```bash
# No built-in coverage tool configured
# Tests rely on manual verification
```

## Test Types

**Unit Tests:**
- Test individual modules in isolation
- Mock all dependencies
- Files: `*_spec.lua` in `tests/modules/*/`
- Example: `tests/modules/todos/linking_spec.lua`

**Integration Tests:**
- Test module interactions
- Minimal mocking (core framework only)
- Files: `tests/shared/*_spec.lua`
- Example: `tests/shared/storage_spec.lua`

**E2E Tests:**
- Not implemented
- UI window tests act as partial E2E via mock vim API

## Common Patterns

**Async Testing:**
```lua
-- Plenary handles async via vim.schedule mock
vim.schedule = function(fn) fn() end

-- For actual async needs (rare):
it("should handle async operation", function()
    local completed = false

    -- trigger async operation
    module.async_function(function()
        completed = true
    end)

    -- wait/assert
    vim.wait(1000, function() return completed end)
    assert.is_true(completed)
end)
```

**Error Testing:**
```lua
it("should return error for invalid input", function()
    local success, message = module.operation("invalid")

    assert.is_false(success)
    assert.equals("Todo index out of range", message)
end)

-- For functions that throw
it("should error on invalid name", function()
    assert.has_error(function()
        registry.register(nil, {})
    end, "Module name must be a string")
end)
```

**Skip pattern:**
```lua
-- Use it.skip() to temporarily disable a test
it.skip("should get all unique tags", function()
    -- test that needs fixing
end)
```

**Window cleanup pattern:**
```lua
after_each(function()
    -- Clean up any open windows
    for _, win in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_get_config(win).relative ~= "" then
            pcall(api.nvim_win_close, win, true)
        end
    end
end)
```

## Docker Test Environment

**Dockerfile:** `docker/Dockerfile`
- Base: Alpine Linux
- Neovim + Lua 5.3 + LuaRocks
- Plenary.nvim pre-installed
- oil.nvim pre-installed (dependency)

**Test execution:**
```bash
# Build image
docker build -t doit-plugin-test docker/

# Run with timeout (60 seconds)
docker run --rm -v "$(pwd):/plugin" doit-plugin-test \
    nvim --headless -c "lua require('plenary.test_harness').test_directory('tests')" -c "qa!"
```

**Test output interpretation:**
- `[32mSuccess[0m` - Green text, test passed
- `[31mFailed[0m` - Red text, test failed
- Summary at end of each file: `Success: N`, `Failed: N`, `Errors: N`

## Assertions Reference

**Common assertions:**
```lua
-- Equality
assert.are.equal(expected, actual)
assert.are_not.equal(unexpected, actual)

-- Boolean
assert.is_true(value)
assert.is_false(value)
assert.is_nil(value)
assert.is_not_nil(value)

-- Type checking
assert.are.equal("table", type(result))
assert.are.equal("function", type(callback))

-- Tables
assert.are.same({ a = 1 }, result)  -- deep comparison
assert.truthy(table_contains(result, item))

-- Strings
assert.truthy(str:match("pattern"))
assert.falsy(str:match("pattern"))

-- Errors
assert.has_error(function() error("boom") end)
assert.has_error(fn, "expected error message")

-- Stub/mock verification (luassert)
assert.stub(mock_fn).was.called(1)
assert.stub(mock_fn).was.called_with(arg1, arg2)
```

---

*Testing analysis: 2026-01-19*
