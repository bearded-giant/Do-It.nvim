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

## Installation

### Prerequisites

- Neovim `>= 0.10.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) as your plugin manager

### Full Framework

```lua
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit").setup({
            -- Framework configuration
            modules = {
                todos = {
                    -- Todos module configuration
                },
                notes = {
                    -- Notes module configuration
                }
            }
        })
    end,
}
```

### Individual Modules

You can also use just the modules you need:

```lua
-- Just the todos module
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit_todos").setup({
            -- Todos configuration
        })
    end,
}

-- Just the notes module
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit_notes").setup({
            -- Notes configuration
        })
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

## Framework Architecture

Do-It.nvim 2.0 introduces a modular framework that allows components to work independently or together. This architecture enables:

- Loading only the modules you need
- Using modules standalone or together
- Adding custom modules that integrate with the system
- Extending functionality without modifying core code

See `:help doit-framework` for details on the framework architecture and module development.

## Default Configuration

```lua
{
    -- Framework configuration
    project = {
        enabled = true,
        detection = {
            use_git = true,
            fallback_to_cwd = true,
        },
        storage = {
            path = vim.fn.stdpath("data") .. "/doit",
        },
    },
    
    plugins = {
        auto_discover = true,
        load_path = "doit.modules",
    },
    
    -- Module configurations
    modules = {
        -- Todos module
        todos = {
            enabled = true,
            save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
            timestamp = { enabled = true },
            window = {
                width = 55,
                height = 20,
                border = "rounded",
                position = "center",
                padding = { top = 1, bottom = 1, left = 2, right = 2 },
            },
            list_window = {
                width = 40,
                height = 10,
                position = "bottom-right",
            },
            formatting = {
                pending = {
                    icon = "○",
                    format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" },
                },
                in_progress = {
                    icon = "◐",
                    format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" },
                },
                done = {
                    icon = "✓",
                    format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" },
                },
            },
            -- See :help doit-configuration for all options
        },
        
        -- Notes module
        notes = {
            enabled = true,
            icon = "📓",
            storage_path = vim.fn.stdpath("data") .. "/doit/notes",
            mode = "project", -- "global" or "project"
            window = {
                width = 0.6,
                height = 0.6,
                border = "rounded",
                title = " Notes ",
                title_pos = "center",
            },
            keymaps = {
                toggle = "<leader>dn",
                close = "q",
                switch_mode = "m",
            },
        },
    }
}
```

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
