# Do-It.nvim

[![Tests](https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml/badge.svg)](https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml)

Do-It.nvim is a modular task management framework for Neovim, providing a clean, distraction-free interface to manage your tasks and notes directly within your editor.

Do-It.nvim began as a way to track tasks and keep simple markdown notes per project. As a Principal Engineer with many disparate things to keep track of, I wanted a simple way to do that without leaving my editor. I've tried many task managers, but they all seemed too complex - I just needed to know what I needed to do, without bells and whistles.

> This project is a fork of [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas), expanded with a modular framework and additional features like project notes.

## Features

- **Modular Framework** - Use only the components you need
- **Task Management** - Create, organize, and track to-dos
- **Project Notes** - Maintain project-specific documentation
- **Tags & Filtering** - Categorize tasks with #tags
- **Due Dates** - Set deadlines with calendar integration
- **Priorities** - Assign and sort by importance
- **Time Estimation** - Track estimated completion time
- **Import/Export** - Backup or share your tasks
- **Lualine Integration** - Show active tasks in your statusline

## Quick Start

### Installation with Lazy.nvim

```lua
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit").setup()
    end,
}
```

### Basic Usage

1. **Open todos**: `:Doit` or `<leader>td`
2. **Add a todo**: Press `i` in the todo window
3. **Toggle status**: Press `x` on a todo
4. **Open notes**: `:DoItNotes` or `<leader>dn`

## Installation Options

### Prerequisites

- Neovim `>= 0.10.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) as your plugin manager

### Full Framework (Recommended)

```lua
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit").setup({
            modules = {
                todos = { enabled = true },
                notes = { enabled = true }
            }
        })
    end,
}
```

### Standalone Modules

Use individual modules without the framework:

```lua
-- Just todos
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit_todos").setup()
    end,
}

-- Just notes
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit_notes").setup()
    end,
}
```

## Commands

- `:Doit` - Opens the main to-do window
- `:Doit add [text]` - Adds a new to-do
  - `-p, --priority [name]` - Set priority (e.g., "important", "urgent")
- `:Doit list` - Lists all to-dos with their metadata
- `:Doit set [index] [field] [value]` - Modifies to-do properties
- `:DoItList` - Toggle a floating window with active to-dos
- `:DoItNotes` - Toggle the project notes window

## Keybindings

| Key           | Action                      |
|--------------|------------------------------|
| `<leader>td` | Toggle to-do window          |
| `<leader>dl` | Toggle active to-dos list    |
| `<leader>dn` | Toggle project notes window  |
| `i`          | Add new to-do                |
| `x`          | Toggle to-do status          |
| `d`          | Delete current to-do         |
| `H`          | Add due date                 |
| `t`          | Toggle tags window           |
| `p`          | Edit priorities              |
| `/`          | Search to-dos                |
| `r`          | Enter reordering mode        |

See `:help doit-keybindings` for a full list of keybindings.

## Modules

### Todos Module

The todos module provides task management functionality:

- Create, edit, and organize to-dos
- Tag-based filtering and organization
- Priority-based sorting
- Due dates with calendar integration
- Time estimation tracking
- Import/export capabilities

### Notes Module

The notes module provides project-specific notes:

- Project-specific notes based on Git repository
- Global notes mode for system-wide documentation
- Markdown syntax highlighting
- Floating window interface
- Automatic saving

## Documentation

- **User Guide**: See `:help doit` in Neovim
- **Framework Documentation**: `:help doit-framework`
- **Developer Documentation**: [docs/](./docs/) directory
- **API Reference**: `:help doit-api`

## Configuration

Do-It.nvim uses a nested configuration structure that separates core framework settings from module-specific options. This makes it easier to navigate and customize.

### Configuration Structure

```lua
require("doit").setup({
    -- Core framework settings
    development_mode = false,
    quick_keys = true,
    timestamp = { enabled = true },
    lualine = { enabled = true, max_length = 30 },
    project = {
        enabled = true,
        detection = { use_git = true, fallback_to_cwd = true },
    },
    
    -- Module configurations
    modules = {
        todos = {
            enabled = true,
            ui = {
                window = {
                    width = 55,
                    height = 20,
                    border = "rounded",
                },
                -- More UI settings...
            },
            formatting = {
                pending = { icon = "○" },
                in_progress = { icon = "◐" },
                done = { icon = "✓" },
            },
            priorities = {
                { name = "critical", weight = 16 },
                { name = "urgent", weight = 8 },
                { name = "important", weight = 4 },
            },
            -- More todos settings...
        },
        notes = {
            enabled = true,
            ui = {
                window = {
                    -- Absolute sizing
                    width = 80,   -- columns
                    height = 30,  -- lines
                    -- Or relative sizing
                    relative_width = 0.6,   -- 60% of screen
                    relative_height = 0.6,  -- 60% of screen
                    use_relative = true,    -- toggle mode
                    position = "center",    -- or top-left, bottom-right, etc.
                },
            },
            storage = {
                path = vim.fn.stdpath("data") .. "/doit/notes",
                mode = "project", -- or "global"
            },
            -- More notes settings...
        },
    },
})
```

### Key Configuration Points

- **Core settings** (top level): Framework-wide configurations like `development_mode`, `lualine`, and `project` detection
- **Module settings** (`modules.todos` and `modules.notes`): Specific to each module, organized into logical groups like `ui`, `storage`, `formatting`, etc.
- **Backward compatibility**: The plugin maintains support for the legacy flat configuration structure

For a complete list of all configuration options with detailed descriptions, see [`lua/doit/config.lua`](./lua/doit/config.lua).

Also see `:help doit-configuration` in Neovim for interactive documentation.

## Lualine Integration

Add your active to-do to Lualine:

```lua
require("lualine").setup({
  sections = {
    lualine_c = {
      -- Other components...
      { require("doit").lualine.active_todo }
    }
  }
})
```

## Contributing

See the [developer documentation](./docs/) for:
- [Development setup and debugging](./docs/development/DEVELOPMENT.md)
- [Framework architecture](./docs/development/framework.md)
- [Module development guide](./docs/modules/)
- [Implementation notes](./docs/implementation/)

## Roadmap

- [x] Reorder To-dos
- [x] Active To-do to Top
- [x] Project Notes
- [x] Modular Framework
- [ ] Named (Multiple) To-do Lists
- [ ] To-do Categories View
- [ ] Cross-module Integration
- [ ] Custom Module Registry

## Acknowledgments

Do-It.nvim is a fork of [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas). Special thanks to him for creating the original plugin.

The project notes feature was inspired by maple.nvim's project notes functionality.

The framework architecture was inspired by other modular Neovim plugins like mini.nvim and snack.nvim.
