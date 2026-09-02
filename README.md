# Do-It.nvim

[![Tests](https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml/badge.svg)](https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml)

Do-It.nvim is a modular task management framework for Neovim, providing a clean, distraction-free interface to manage your tasks and notes directly within your editor.

Do-It.nvim began as a way to track tasks and keep simple markdown notes per project. As a Principal Engineer with many disparate things to keep track of, I wanted a simple way to do that without leaving my editor. I've tried many task managers, but they all seemed too complex - I just needed to know what I needed to do, without bells and whistles.

> This project is a fork of [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas), expanded with a modular framework and additional plugins such ash project notes, and calendar..

## Features

- **Modular Framework** - Use only the components you need
- **Task Management** - Create, organize, and track to-dos
- **Nested To-dos** - Break a task into subtasks with `a`; a subtree stays together in nvim, tmux, and the MCP server
- **Project Notes** - Maintain project-specific documentation
- **Tags & Filtering** - Categorize tasks with #tags
- **Due Dates** - Set deadlines with calendar integration
- **Priorities** - Assign and sort by importance
- **Time Estimation** - Track estimated completion time
- **Import/Export** - Backup or share your tasks, or export pending items to markdown with `E`
- **Lualine Integration** - Show active tasks in your statusline
- **Tmux Add-on** - Optional tmux integration with shared data (see below)
- **Session-Linked Lists** - Each tmux session holds its own active list; `daily` stays one popup away

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
2. **Add a todo**: Press `n` in the todo window
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

- `n` - Add new todo
- `a` - Add a child todo under the current one
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
- Nested subtasks, rendered indented under their parent
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

## Tmux Integration (Optional Add-on)

> **Note**: The tmux integration is a separate, optional add-on that shares data with the Neovim plugin. You can use doit.nvim without tmux, or use both together for a seamless experience across your terminal workflow.

The tmux add-on provides todo management directly from tmux, with status bar integration and an interactive fzf-based manager. Changes sync automatically between Neovim and tmux.

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
| `n` | New todo                  |
| `N` | Start next pending todo   |
| `l` | Switch lists (links the current session) |
| `L` | List manager              |
| `d` | Daily list popup (pinned to `daily`) |

**Direct shortcuts (Alt+Shift):**

| Key           | Action              |
|---------------|---------------------|
| `Alt+Shift+T` | Quick todo popup    |
| `Alt+Shift+I` | Interactive manager |
| `Alt+Shift+X` | Toggle todo done    |
| `Alt+Shift+N` | New todo            |
| `Alt+Shift+L` | Switch lists        |
| `Alt+Shift+D` | Daily list popup    |

**In interactive manager:**

| Key     | Action                |
|---------|-----------------------|
| `Enter` | Toggle done           |
| `K`/`J` | Reorder (a parent moves with its subtree) |
| `s`     | Start/In-progress     |
| `x`     | Stop in-progress      |
| `X`     | Revert to pending     |
| `n`     | New todo              |
| `e`     | Edit todo text        |
| `d`     | Delete (can undo)     |
| `u`     | Undo last delete      |
| `E`     | Export to markdown    |
| `?`     | Show help             |
| `q`     | Quit                  |

In create/edit mode: type text, Enter twice to save, Esc to cancel.

### Configuration

```bash
# Change the prefix key (default: d)
set -g @doit-key "t"

# Disable Alt+Shift shortcuts
set -g @doit-alt-bindings "off"

# Use $EDITOR (nvim, vim) for create/edit instead of inline input
set -g @doit-use-editor "true"

# Interactive manager popup size (default: 80% x 80%)
# Accepts absolute cells ("120") or terminal-relative percentages ("80%")
set -g @doit-interactive-popup-w "80%"
set -g @doit-interactive-popup-h "80%"

# Where `E` writes markdown exports (default: the popup's working directory)
set -g @doit-export-dir "~/notes/exports"

# Per-project lists: a pane inside a git repo uses a list named after the
# repo directory, created on first use (default: off)
set -g @doit-project-lists "on"
```

### Session-Linked Lists

Each tmux session can hold its own active list. The link map lives in `session.json` (`sessions: {"<tmux session>": "<list>"}`), so links survive tmux restarts, and every surface resolves the active list through the same chain:

1. `DOIT_ACTIVE_LIST` environment override
2. The current tmux session's link
3. Per-project derivation (`@doit-project-lists`, opt-in)
4. The global `.active_list` pointer
5. `daily`

Outside tmux the session step is skipped and everything behaves like before.

In the list switcher (`prefix + d + l`) and list manager (`prefix + d + L`), `Enter` links the selected list to the current session (and refreshes the global pointer), `g` sets the global pointer only, and `u` unlinks the current session (in the switcher these are `ctrl-g` and `ctrl-u`, so plain letters keep filtering as you type). Rows show which sessions link each list, with dead sessions dimmed, and `daily` stays pinned to the top with its pending count. `prefix + d + d` (or `Alt+Shift+D`) opens the interactive manager pinned to `daily` from any session without touching any link.

### Status Bar Integration

If using [bearded-giant-tmux](https://github.com/bearded-giant/bearded-giant-tmux) theme, add `todo` to your status modules:

```bash
set -g @bearded_giant_status_modules_right "meetings todo"
```

For other themes, use the status script directly:

```bash
set -g status-right "#(~/.tmux/plugins/do-it.nvim/tmux/scripts/todo-status.sh '#{session_name}')"
```

Passing `#{session_name}` lets the status segment resolve the session's linked list; status commands run without a client context, so the script cannot discover the session on its own.

## MCP Server (Claude Code Integration)

Do-it.nvim includes an MCP server that exposes your todo lists to [Claude Code](https://claude.ai/code) and other MCP-compatible tools. This lets you read, create, update, and search todos without leaving your AI coding session.

### Setup

```bash
cd mcp && npm install
```

Add to your Claude Code `settings.json` under `mcpServers`:

```json
{
  "doit": {
    "command": "node",
    "args": ["/path/to/do-it.nvim/mcp/server.js"]
  }
}
```

If you configured a custom storage path in your do-it.nvim setup (via `modules.todos.storage.save_path`), set `DOIT_DATA_DIR` to match:

```json
{
  "doit": {
    "command": "node",
    "args": ["/path/to/do-it.nvim/mcp/server.js"],
    "env": {
      "DOIT_DATA_DIR": "/your/custom/data/path"
    }
  }
}
```

### Available Tools

Todo items:

| Tool | Description |
|------|-------------|
| `list_todos` | List items from a list, filtered by status, priority, #tag and/or due date |
| `search_todos` | Search every list for items matching a text pattern |
| `list_tags` | List the inline #tags on a list, with usage counts |
| `add_todo` | Create a todo, composing the text from `type`, `deps`, and an auto-assigned rank. Takes `due` and `parent` (nest under another item) |
| `update_todo` | Edit text, description, status, priority, due date, order, or `parent`. Needs an id |
| `start_todo` | Mark an item in progress. Fuzzy text query; only one item runs at a time |
| `complete_todo` | Mark an item done. Fuzzy text query; with no args it looks at in-progress items |
| `revert_todo` | Send an item back to pending |
| `delete_todo` | Delete an item, keeping it in `_metadata.deleted_todos` for undo |
| `clear_done` | Delete every completed item in a list, keeping the last 10 for undo |
| `dedupe_todos` | Remove items whose text matches after normalization. Dry run by default |
| `move_todo` | Move an item to another list |

Notes. Two different things share the word: `add_note` writes the description on a todo item, while the `*_note` tools manage standalone list-scoped notes.

| Tool | Description |
|------|-------------|
| `add_note` | Write a note onto a todo item. Appends by default; `mode='replace'` overwrites |
| `list_notes` | List the standalone notes on a list, returning titles and ids |
| `get_note` | Read one list note in full |
| `create_note` | Create a standalone list note, not attached to any todo |
| `update_note` | Update a list note's title and/or body. Replaces by default; `mode='append'` adds |
| `delete_note` | Delete a list note, keeping the last 10 for undo |

Lists:

| Tool | Description |
|------|-------------|
| `list_lists` | Show all lists, which one is active, and which tmux sessions link each |
| `switch_list` | Change the active list. Inside tmux it links the current session and updates the global pointer; `scope` narrows the write to `session` or `global` |
| `create_list` | Create a new empty list. Inside tmux it auto-links the new list when the session has none, and asks before relinking otherwise |
| `rename_list` | Rename a list. Switch away from it first |
| `delete_list` | Delete a list. Switch away from it first |

### Item Text Convention

Items the MCP server creates get a scannable title instead of a bare sentence:

```
claude: [gate] 41. pre-store gate check (dep on #40)
```

You pass `type` (a short free-form tag like `gate`, `decision`, `comms`) and `deps` (the rank numbers of blocking items) as params — the server composes the final text. The rank number is assigned automatically from the highest one already in the list, so priority stays the bucket and the number tells you the order inside it. `update_todo` keeps an item's rank when you rewrite its text, and takes `type` / `deps` to retype or re-point it later. Composing is idempotent, so prefixes never stack.

Duplicate detection strips that whole wrapper before comparing, so an item you typed in Neovim as `buy milk` matches the one MCP stored as `claude: [chore] 3. buy milk (dep on #1)`. Comparison ignores the `claude:` marker, the `[type]` tag, the rank prefix, the `(dep on #N)` suffix, case, and whitespace. A `[[note link]]` prefix is not a type tag and survives, and a number without a following space (`3.buy milk`, `1.5x throughput`) is not a rank. When duplicates are collapsed the copy carrying real notes wins, and the rest go to the undo stack — `<leader>D` in Neovim confirms first, and `dedupe_todos` is a dry run unless you pass `dry_run:false`.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOIT_DATA_DIR` | `~/.local/share/nvim/doit` | Data directory path |
| `DOIT_ACTIVE_LIST` | (unset) | Override active list name. Wins over session links and per-project derivation |

The MCP server reads and writes the same JSON files used by the Neovim plugin and tmux add-on. Changes sync automatically.

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
