# DoIt Plugin Development Guide

This guide explains how to set up a development environment for the DoIt plugin. It assumes you're already familiar with the basics of Docker, Lua, and Neovim plugin development.

## Prerequisites

- Docker
- Git
- Basic understanding of Lua and Neovim's API

## Development Environment

The project uses a Docker-based development environment to ensure consistency and isolate dependencies. This approach allows us to:

1. Test against specific Neovim versions
2. Maintain a clean development environment
3. Ensure tests run in a consistent environment

## Running Tests

The test suite uses Plenary.nvim for testing. To run the tests:

```bash
# Run all tests
./docker/run-tests.sh

# Run specific test file(s)
./docker/run-tests.sh tests/state/todos_spec.lua

# Run specific test file with pattern
./docker/run-tests.sh tests/state/todos_spec.lua --pattern="add_todo"
```

Tests are located in the `tests/` directory and follow the pattern `*_spec.lua`. The Docker container ensures all tests run in a clean environment.

## Interactive Development

For interactive development, use the interactive mode:

```bash
./docker/run-interactive.sh
```

This mounts your local codebase into the container, so any changes you make locally are immediately available in the container.

### Live Reload

The plugin includes a live reload feature for development:

1. Inside the container, open Neovim
2. Enable auto-reload with `:DoitAutoReload`
3. Edit files on your local machine
4. The plugin will automatically reload in the container when you save

You can also manually reload with `:DoitReload` if needed.

## Minimal Lua Setup

The plugin uses a minimal Lua setup for several reasons:

1. **Performance**: Minimal dependencies mean faster loading and execution
2. **Simplicity**: Easier to understand and maintain the codebase
3. **Compatibility**: Fewer dependencies reduce the risk of version conflicts

### Project Structure

The plugin follows the standard Neovim plugin structure:

```
lua/doit/
├── init.lua         # Main entry point
├── config.lua       # Configuration management
├── state/           # Data management
│   ├── todos.lua    # Todo CRUD operations
│   ├── storage.lua  # Persistence layer
│   └── sorting.lua  # Sorting algorithms
└── ui/              # User interface components
    ├── main_window.lua     # Main window rendering
    └── todo_actions.lua    # User interactions
```

### Module Pattern

We use the local module pattern throughout the codebase:

```lua
local M = {}

function M.some_function()
  -- Implementation
end

return M
```

This pattern helps with code organization and avoids global namespace pollution.

## Testing Philosophy

Tests are divided into two categories:

1. **State tests**: Verify the correctness of the data management logic
2. **UI tests**: Verify the user interface behaviors

Each feature should have corresponding tests in both categories when applicable.

## Adding New Features

When adding new features:

1. Start by adding tests that describe the expected behavior
2. Implement the feature
3. Update documentation (help file and README)
4. Ensure all tests pass

## Making Releases

1. Update the version in the plugin metadata
2. Run the full test suite
3. Update the changelog
4. Create a git tag
5. Push to GitHub

## Debugging

For debugging, the plugin uses `vim.notify()` with appropriate log levels:

```lua
vim.notify("Info message", vim.log.levels.INFO)
vim.notify("Warning message", vim.log.levels.WARN)
vim.notify("Error message", vim.log.levels.ERROR)
```

## Contributing

Contributions are welcome! Please ensure:

1. Code follows the existing style (4 spaces for indentation)
2. All tests pass
3. New features include tests
4. Documentation is updated