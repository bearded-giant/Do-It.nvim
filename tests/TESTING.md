# do-it.nvim Test Structure

This directory contains all tests for the do-it.nvim framework and its modules.

## Directory Organization

### `/core/`
Core framework tests that validate the fundamental components:
- `framework_spec.lua` - Main framework initialization and setup
- `registry_spec.lua` - Module registry and plugin system
- `ui/modal_spec.lua` - Core UI modal component

### `/modules/`
Module-specific tests organized by module name. Each module directory contains:
- Main module tests (e.g., `todos_spec.lua`, `notes_spec.lua`)
- State management tests (`state_spec.lua`)
- UI component tests (`ui_spec.lua`)
- Feature-specific tests (e.g., `linking_spec.lua`, `priority_order_spec.lua`)

#### Plugin Developer Guide
When creating a new module/plugin, create a directory under `/modules/` with your module name:
```
tests/modules/your_module/
├── your_module_spec.lua    # Main module tests
├── state_spec.lua          # State management tests
├── ui_spec.lua             # UI component tests
└── [feature]_spec.lua      # Feature-specific tests
```

### `/shared/`
Generic utilities and components that can be used by multiple modules:
- `storage_spec.lua` - Generic storage functionality
- `sorting_spec.lua` - Sorting utilities
- `tags_spec.lua` - Tagging system
- `reordering_spec.lua` - Item reordering logic
- `ui_reordering_spec.lua` - UI reordering components

### `/legacy/`
Tests from the pre-framework architecture. These are being gradually migrated or removed:
- `doit_spec.lua` - Old monolithic plugin tests
- `main_window_spec.lua` - Old UI tests
- `search_window_spec.lua` - Old search functionality

## Running Tests

Run all tests:
```bash
nvim --headless -c "lua require('plenary.test_harness').test_directory('tests')" -c "qa!"
```

Run tests for a specific module:
```bash
nvim --headless -c "lua require('plenary.test_harness').test_directory('tests/modules/todos')" -c "qa!"
```

Run a specific test file:
```bash
nvim --headless -c "lua require('plenary.test_harness').test_directory('tests', {pattern = 'todos_spec'})" -c "qa!"
```

## Test Conventions

1. Use `describe()` blocks to group related tests
2. Use `before_each()` to set up test state
3. Use `after_each()` to clean up (close windows, restore mocks, etc.)
4. Mock vim APIs and external dependencies
5. Test both success and failure cases
6. Keep tests focused and independent

## Example Test Structure

```lua
describe("my_module", function()
    local my_module
    
    before_each(function()
        -- Clear module cache
        package.loaded["doit.modules.my_module"] = nil
        
        -- Set up mocks
        -- ...
        
        -- Load module
        my_module = require("doit.modules.my_module")
    end)
    
    after_each(function()
        -- Clean up
    end)
    
    it("should do something", function()
        -- Test implementation
        assert.equals(expected, actual)
    end)
end)
```