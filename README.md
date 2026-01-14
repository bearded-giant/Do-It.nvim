# Do-It.nvim

[![Tests](https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml/badge.svg)](https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml)

Do-It.nvim is a modular task management framework for Neovim, providing a clean, distraction-free interface to manage your tasks and notes directly within your editor.

Do-It.nvim began as a way to track tasks and keep simple markdown notes per project. As a Principal Engineer with many disparate things to keep track of, I wanted a simple way to do that without leaving my editor. I've tried many task managers, but they all seemed too complex - I just needed to know what I needed to do, without bells and whistles.

> This project is a fork of [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas), expanded with a modular framework and additional plugins such ash project notes, and calendar..

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
- **Tmux Integration** - Manage todos from tmux with status bar and fzf

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

-- Calendar (v2.0) - macOS only, requires icalbuddy
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit").setup({
            modules = {
                calendar = { enabled = true }
            }
        })
    end,
}
```

## Commands & Keybindings

See [**Complete Keybindings Reference**](docs/KEYBINDINGS.md) for all commands and keyboard shortcuts.

### Quick Reference

**Framework Commands:**

- `:DoItDashboard` - Open main DoIt dashboard
- `:DoItPlugins list` - List installed modules
- `:DoItPlugins info <module>` - Show module details

**Module Commands:**

_Todos:_

- `:DoIt` - Open main todo window
- `:DoItList` - Quick todo list (floating)
- `:DoItLists` - Manage multiple todo lists

_Notes:_

- `:DoItNotes` - Open notes window
- `:DoItNotesNew` - Create new project note
- `:DoItNotesSearch` - Search across notes

_Calendar (macOS only):_

- `:DoItCalendar` - Toggle calendar window
- `:DoItCalendarDay` - Open in day view
- `:DoItCalendar3Day` - Open in 3-day view
- `:DoItCalendarWeek` - Open in week view

**Basic Keys (in todo window):**

- `i` - Add new todo
- `x` - Toggle status
- `d` - Delete todo
- `?` - Show full help
- `L` - List manager
- `q` - Close window

The keybindings documentation is auto-generated from a central source to ensure consistency. Run `make update-help` to regenerate after changes.

## Modules

### Todos Module

The todos module provides task management functionality:
[Full Documentation](docs/modules/todos.md)

- Create, edit, and organize to-dos
- Tag-based filtering and organization
- Priority-based sorting
- Due dates with calendar integration
- Time estimation tracking
- Import/export capabilities

### Notes Module

The notes module provides project-specific notes:
[Full Documentation](docs/modules/notes.md) | **Work in Progress**

- Project-specific notes based on Git repository
- Global notes mode for system-wide documentation
- Markdown syntax highlighting
- Floating window interface
- Automatic saving

### Calendar Module (v2.0)

The calendar module provides macOS calendar integration:
[Full Documentation](lua/doit/modules/calendar/README.md) | [Module Docs](docs/modules/calendar.md)

- **icalbuddy Integration**: View events from macOS Calendar app
- **Multiple Views**: Day, 3-day, and week views
- **Smart Parsing**: Handles 100% of icalbuddy event formats
- **UTF-8 Support**: Correctly displays special characters
- **Auto-refresh**: Updates when switching views
- **All Calendar Sources**: iCloud, Google, Exchange support

_Note: Requires macOS with icalbuddy installed (`brew install icalbuddy`)_

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

Do-It.nvim provides several lualine components to display todo information in your statusline:

```lua
require("lualine").setup({
  sections = {
    lualine_c = {
      -- Show current list and todo count
      { require("doit").lualine.current_list },

      -- Show todo statistics (done/in-progress/pending)
      { require("doit").lualine.todo_stats },

      -- Show active (in-progress) todo
      { require("doit").lualine.active_todo }
    }
  }
})
```

Available components:

- `current_list` - Shows current list name and todo count: `📋 work (5)`
- `todo_stats` - Shows todo statistics: `✓3 ◐1 ○2` (done/in-progress/pending)
- `active_todo` - Shows the current in-progress todo (if any)

## Tmux Integration

Do-It.nvim includes a tmux plugin for managing todos directly from tmux, with status bar integration and an interactive fzf-based manager.

### Prerequisites

- [tmux](https://github.com/tmux/tmux) with [TPM](https://github.com/tmux-plugins/tpm)
- [fzf](https://github.com/junegunn/fzf) for interactive mode
- [jq](https://stedolan.github.io/jq/) for JSON parsing

### Installation

Add to your `tmux.conf`:

```bash
set -g @plugin 'bearded-giant/do-it.nvim'
```

Then install with `prefix + I`.

### Keybindings

**With prefix key (`prefix + d + ...`):**

| Key | Action                    |
|-----|---------------------------|
| `t` | Quick todo popup          |
| `i` | Interactive manager (fzf) |
| `x` | Toggle current todo done  |
| `n` | Start next pending todo   |
| `c` | Create new todo           |

**Direct shortcuts (Alt+Shift):**

| Key           | Action              |
|---------------|---------------------|
| `Alt+Shift+T` | Quick todo popup    |
| `Alt+Shift+I` | Interactive manager |
| `Alt+Shift+X` | Toggle todo done    |
| `Alt+Shift+N` | Start next todo     |

**In interactive manager:**

| Key     | Action                |
|---------|-----------------------|
| `Enter` | Toggle done           |
| `s`     | Start/In-progress     |
| `x`     | Stop in-progress      |
| `X`     | Revert to pending     |
| `c`     | Create new todo       |
| `r`     | Refresh               |
| `q/ESC` | Quit                  |

### Configuration

```bash
# Change the prefix key (default: d)
set -g @doit-key "t"

# Disable Alt+Shift shortcuts
set -g @doit-alt-bindings "off"
```

### Status Bar Integration

If using [bearded-giant-tmux](https://github.com/bearded-giant/bearded-giant-tmux) theme, add `todo` to your status modules:

```bash
set -g @bearded_giant_status_modules_right "meetings todo"
```

For other themes, use the status script directly:

```bash
set -g status-right "#(~/.tmux/plugins/do-it.nvim/tmux/scripts/todo-status.sh)"
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
- [x] To-do Categories (with filtering)
- [x] Cross-module Integration (todo-note linking)
- [x] Module Registry (internal modules)
- [x] Named (Multiple) To-do Lists
- [x] Categories View Window
- [x] External/Custom Module Loading

## Acknowledgments

Do-It.nvim started as fork of [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas). Special thanks to him for creating the original plugin.

The project notes feature was inspired by maple.nvim's project notes functionality.

The framework architecture was inspired by other modular Neovim plugins like mini.nvim and snack.nvim.
