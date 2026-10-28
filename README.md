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
- **Window-Linked Lists** - Each tmux window holds its own active list; `daily` stays one popup away

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

- `<CR>` - Add new todo
- `a` - Add a child todo under the current one
- `c` - Toggle status (pending → in-progress → done)
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
| `l` | Switch lists (links the current window) |
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

| Key       | Action                |
|-----------|-----------------------|
| `Enter`   | Open item/note in nvim (view, edit its note) |
| `s`       | Start (in-progress)   |
| `x`       | Complete (done)       |
| `X`       | Revert to pending     |
| `n` / `p` | New todo (in the Notes section: new note) / paste new from clipboard |
| `e`       | Edit todo text        |
| `P`       | Set priority          |
| `N`       | Edit note (description) |
| `g`       | List notes modal      |
| `K`/`J`   | Reorder (a parent moves with its subtree) |
| `[`/`]`   | Jump section down/up  |
| `m`       | Move todo to another list |
| `l` / `L` | Switch list / list manager |
| `t` / `c` | Filter by #tag / clear filter |
| `h`       | Set or clear due date |
| `S`       | Set or clear sequence (run order across priorities) |
| `/`       | Search                |
| `d` / `D` | Delete todo / clear all completed |
| `u`       | Undo last delete      |
| `E`       | Export pending to markdown |
| `O`       | Send to Obsidian daily note |
| `y` / `Y` | Copy todo text / list name |
| `i`       | Copy item id (the MCP resolves it across lists) |
| `?`       | Show help             |
| `q` / `Esc` | Back to lists / quit |

In create/edit mode: type text, Enter twice to save, Esc to cancel.

### Configuration

```bash
# Change the prefix key (default: d)
set -g @doit-key "t"

# Disable Alt+Shift shortcuts
set -g @doit-alt-bindings "off"

# Use $EDITOR (nvim, vim) for create/edit instead of inline input
set -g @doit-use-editor "true"

# Interactive manager and list switcher/manager popup size (default: 80% x 80%)
# Accepts absolute cells ("120") or terminal-relative percentages ("80%")
set -g @doit-interactive-popup-w "80%"
set -g @doit-interactive-popup-h "80%"

# Where `E` writes markdown exports (default: the popup's working directory)
set -g @doit-export-dir "~/notes/exports"

# Per-project lists: a pane inside a git repo uses a list named after the
# repo directory, created on first use (default: off)
set -g @doit-project-lists "on"
```

### Window-Linked Lists

Each tmux window can hold its own active list, so worktrees opened as windows of one session each keep their own todos. The link lives on the window itself as the `@doit-window-list` tmux option, so it follows the window through renames, moves to another session, and session renames, and two windows with the same name keep separate lists. A copy goes to `session.json` (`sessions: {"<tmux session>:<window name>": "<list>"}`); after a tmux restart each window takes back the link saved under its name, and the plugin's `window-renamed`, `session-renamed` and `window-linked` hooks keep that copy on the current name. Every surface resolves the active list through the same chain:

1. `DOIT_ACTIVE_LIST` environment override
2. The current tmux window's link
3. Per-project derivation (`@doit-project-lists`, opt-in)
4. `daily`

An unlinked tmux window always lands on `daily`, never on whichever list was switched to last elsewhere. Outside tmux the window step is skipped and the global `.active_list` pointer takes the place of `daily` (falling back to `daily` when unset).

Links from older versions bound whole tmux sessions. When the plugin loads, each running window of such a session that has no link of its own takes the session's list, and the session entry goes away, so no window changes list on upgrade.

The MCP server is the exception. Links track what you are looking at, which is rarely the list a model's work belongs to, so the server ignores them and the global pointer: a call without `list` goes to `DOIT_ACTIVE_LIST` when set, else `daily`. Model sessions pass `list` explicitly for project work.

In the list switcher (`prefix + d + l`), `Enter` links the selected list to the current window (and refreshes the global pointer). In the list manager (`prefix + d + L`, or `L`/`q` from the interactive manager), `Enter` opens the list to view and edit without touching any link, and `l` does the linking instead. In both, `g` sets the global pointer only, and `u` unlinks the current window (in the switcher these are `ctrl-g` and `ctrl-u`, so plain letters keep filtering as you type). Rows show which windows link each list as `session:window`, with dead windows dimmed, and `daily` stays pinned to the top with its pending count. A list holding open items past their due date is badged `!N overdue` (the preview repeats the count), and the nvim list manager badges the row `!M name (N todos)` in red. `prefix + d + d` (or `Alt+Shift+D`) opens the interactive manager pinned to `daily` from any window without touching any link.

### List Source

If Claude Code sessions make a list per repo or feature, those lists pile up fast and bury yours. So every list is either yours or Claude's. A list is yours when its `_metadata.source` is `"user"`, and `daily` always is. Everything else counts as Claude's, unflagged lists included, so session lists stay out of your way without anyone stamping them. Lists you create in the tmux list manager or in Neovim get stamped as yours.

One view filter (`source_filter` in `session.json`: `all`, `mine`, or `claude`, unset means `all`) drives every list view, so flip it anywhere and the rest follow. It only changes what the views show. Active-list resolution, window links, and the MCP server ignore it, so a Claude session can still work in any list, yours included.

| Surface | Cycle the view | Flip a list mine/claude |
|---------|----------------|-------------------------|
| Pane board (tmux popup or WezTerm split) | `s` | `S` on a list row |
| tmux list manager (`prefix + d + L`) | `s` | `S` |
| tmux list switcher (`prefix + d + l`) | `ctrl-s` | `ctrl-f` |
| Neovim list manager (`L`) | `s` | `S` |
| MCP server | `set_source_filter` | `set_list_source` |

Your lists carry a green `mine` tag after the name in every list view, `daily` included. The list manager and switcher always show the active list, even when the view would hide it.

### Status Bar Integration

If using [bearded-giant-tmux](https://github.com/bearded-giant/bearded-giant-tmux) theme, add `todo` to your status modules:

```bash
set -g @bearded_giant_status_modules_right "meetings todo"
```

For other themes, use the status script directly:

```bash
set -g status-right "#(~/.tmux/plugins/do-it.nvim/tmux/scripts/todo-status.sh #{window_id})"
```

Passing `#{window_id}` lets the status segment resolve the window's linked list; status commands run without a client context, so the script cannot discover the window on its own. By hand, any tmux target works as the argument, such as `'work:api'`.

### Pane Board

The chip shows one window at a time. If you run a few Claude Code sessions side by side, `tmux/scripts/todo-board.sh` shows them all at once, plus every list. The top section has one row per pane with `@claude_state` set, grouped by session: its status glyph, window, list, and that list's in-progress item. The glyphs follow the usual claude strip rules (busy, ask, ready, error, age, low context). A pane's list is its `@doit-pane-list` option, then its window's link, then `daily`, so two Claude panes sharing a window each keep their own list. Your Claude Code hooks set both pane options; a SessionStart hook can run `tmux set -p -t "$TMUX_PANE" @doit-pane-list <list>`.

Below that comes every list in three groups, `daily` first in whichever group it lands in and the rest by name. ACTIVE holds lists with an in-progress item, shown underneath. OPEN holds lists with open items but nothing in progress, and lists sharing a first dash segment (`auth-*`, `merchant-mcp-*`) fold into one row until you open it. EMPTY is a single line naming the lists with nothing open, and it opens like a fold. A list a Claude pane is working on is left out, since its row is already up top (`daily` always stays). Open counts sit in one aligned column, and the windows linked to a list show only while its row is selected.

Rows are never cut short. The screen is a window onto the whole board, so long rows scroll sideways and a long board scrolls down, with a footer showing where you are. `/` filters as you type, matching list names and item text. A list that matches only on item text shows just those items, and folds open flat while a filter is on.

| Key | Does |
|---|---|
| up/down, `j`/`k` | move the selection |
| enter, click | on a Claude row, switch the tmux client to that pane; on a list, show all its open items; on a fold, open it; on an item, open the todo manager for its list with that item under the cursor |
| `e`, right-click | open the todo manager for the selected list |
| `L` | open the list manager on the selected list (rename, delete) |
| `a` | open or close every list and fold |
| `/` | filter; enter keeps it, esc clears it |
| left/right, `h`/`l`, sideways wheel | scroll sideways |
| wheel, `ctrl-d`/`ctrl-u`, `g`/`G` | scroll down and up |
| `q` | quit |

The board runs outside tmux, so you can park it in a terminal split next to the tmux client and leave it open. It redraws only when something changes, and `--once` prints the whole board without the viewport. A jump moves the tmux client in the pane to the board's right and focuses it, or the most recently active client when there's no WezTerm. Here's a WezTerm key that opens it on the left and closes it again:

```lua
{
  key = "d",
  mods = "CMD|SHIFT",
  action = wezterm.action_callback(function(_, pane)
    local tab = pane:tab()
    if not tab then return end
    for _, p in ipairs(tab:panes()) do
      if p:get_user_vars().doit_board then
        p:send_text("q")
        return
      end
    end
    pane:split({
      direction = "Left",
      size = 0.2,
      args = { "/bin/bash", "-lc", wezterm.home_dir .. "/.tmux/plugins/do-it.nvim/tmux/scripts/todo-board.sh" },
    })
  end),
},
```

The managers open as popups on the tmux client next to the board, so complete, delete, and the rest work exactly as they do from `prefix + d`. Both take a starting point if you want the same jump elsewhere: `todo-interactive.sh --list <name> --item <id>` and `todo-list-manager.sh --select <name>`.

The board marks its pane with the `doit_board` user var, which is how the key finds it again. Set `config.swallow_mouse_click_on_pane_focus = false` so the first click on the board jumps instead of only focusing it.

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
| `get_todo` | Fetch one item by id from whichever list holds it, no list name needed |
| `search_todos` | Search every list for items matching a text pattern |
| `list_tags` | List the inline #tags on a list, with usage counts |
| `add_todo` | Create a todo, composing the text from `type`, `deps`, and an auto-assigned rank. Takes `due`, `parent` (nest under another item), `sequence`, and `owe` (also write a linked twin into `daily`) |
| `update_todo` | Edit text, description, status, priority, due date, order, `sequence`, or `parent`. Needs an id |
| `sequence_todos` | Set a list's whole run order in one call from ranks or ids. Everything not named loses its sequence |
| `start_todo` | Mark an item in progress. Fuzzy text query; only one item runs at a time |
| `complete_todo` | Mark an item done. Fuzzy text query; with no args it looks at in-progress items |
| `revert_todo` | Send an item back to pending |
| `delete_todo` | Delete an item, keeping it in `_metadata.deleted_todos` for undo |
| `clear_done` | Delete every completed item in a list, keeping the last 10 for undo |
| `dedupe_todos` | Remove items whose text matches after normalization. Dry run by default |
| `move_todo` | Move an item to another list |

Ids are global. Copy one from the tmux item view (`i`) or the nvim item view
(`y`), paste it at the model, and `get_todo`, `start_todo`, `complete_todo`,
`revert_todo`, `update_todo`, `add_note`, `delete_todo` and `move_todo` all
find the list that holds it.

Owed items. `add_todo` with `owe: true` is for actions only the user can do
on a project and that something waits on right now: a console or vault
setting, a credential, a message to someone. Routine flow (merging or
reviewing an MR, tagging a release, resuming a session) stays out, so `daily`
reads as signal. It writes the item on the
project list as `[type] N. owed in daily #M: ...` and a twin on `daily` as
`[type] M. <project list>: ...`. Each carries a `twin` field and a first
description line pointing at the other, so `daily` collects what you owe across
every project and each project list still shows it. `complete_todo`,
`revert_todo`, `delete_todo`, `move_todo`, `rename_list`, and `update_todo`'s
done / priority / due keep both twins in step. The tmux and nvim UIs do the
same for done, priority, due, delete (undo brings the twin back too), move, and
list rename. Since `daily` holds every twin, none of the three will delete or
rename it. The tmux and nvim views of `daily` show only items checked off
today; older done items stay in the file (and in `list_todos`), just hidden.
Other lists show every done item.

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
| `list_lists` | Show all lists, which one is active, which tmux windows link each, and whose each is (`[mine]` or `[claude]`). `source` narrows it to `mine` or `claude` |
| `set_list_source` | Mark a list as yours (`user`) or Claude's (`mcp`). See [List Source](#list-source) |
| `set_source_filter` | Set the shared view filter (`mine`, `claude`, `all`) the tmux and nvim list views follow |
| `switch_list` | Change the active list. Inside tmux it links the current window and updates the global pointer; `scope` narrows the write to `window` (or its older name `session`) or `global` |
| `create_list` | Create a new empty list. It links nothing; `switch_list` does that |
| `rename_list` | Rename a list. Switch away from it first |
| `delete_list` | Delete a list. Switch away from it first |

### Item Text Convention

Items the MCP server creates get a scannable title instead of a bare sentence:

```
claude: [gate] 41. pre-store gate check (dep on #40)
```

You pass `type` (a short free-form tag like `gate`, `decision`, `bug`) and `deps` (the rank numbers of blocking items) as params — the server composes the final text. The rank number is assigned automatically from the highest one already in the list and never changes, so deps and `#N` references stay valid. It's a handle, not the work order. When items need to run in a set order, give them a sequence (`sequence_todos`, or `S` in nvim and tmux). Sequenced pending items get their own Sequence section above the priority groups and run in that order no matter their priority, and `/burn`-style workers see them first in `list_todos`. `update_todo` keeps an item's rank when you rewrite its text, and takes `type` / `deps` to retype or re-point it later. The `claude:` burn-down marker carries over too, so pass `claude: false` to drop it once an item is no longer model work. Composing is idempotent, so prefixes never stack.

Keep the body a short label, 40 characters or so, because it's what the tmux chip and the board show. Paths, commands, sub-steps, and the reasoning go in the item's description, and the tool docs ask models for exactly that.

Every item the server writes also gets `source: "mcp"`. Both views use that (or, for older items, the title shape above and owed-twin links) to split a mixed list into a `Mine` block on top and a `Claude` block below, so the things you typed or imported from a vault note don't get buried under a pile of owed items. Lists with only one kind of item look the same as before.

Duplicate detection strips that whole wrapper before comparing, so an item you typed in Neovim as `buy milk` matches the one MCP stored as `claude: [chore] 3. buy milk (dep on #1)`. Comparison ignores the `claude:` marker, the `[type]` tag, the rank prefix, the `(dep on #N)` suffix, case, and whitespace. A `[[note link]]` prefix is not a type tag and survives, and a number without a following space (`3.buy milk`, `1.5x throughput`) is not a rank. When duplicates are collapsed the copy carrying real notes wins, and the rest go to the undo stack — `<leader>D` in Neovim confirms first, and `dedupe_todos` is a dry run unless you pass `dry_run:false`.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOIT_DATA_DIR` | `~/.local/share/nvim/doit` | Data directory path |
| `DOIT_ACTIVE_LIST` | (unset) | Override active list name. Wins over window links and per-project derivation. The MCP server reads only this, then `daily` |

The MCP server reads and writes the same JSON files used by the Neovim plugin and tmux add-on. Changes sync automatically.

## Obsidian Vault Export

Want your lists in Obsidian, next to the rest of your notes? `mcp/vault-export.js` mirrors every list into a vault folder: one folder per list, one note per item, so you can browse items and read their notes without a popup covering your panes. It's one-way. Edit todos through Neovim, tmux, or MCP, and the vault copy follows. Anything you change in an exported note gets overwritten on the next export.

```bash
node mcp/vault-export.js <vault>/doit-todos            # export once
node mcp/vault-export.js <vault>/doit-todos --watch    # export, then re-export whenever a list changes
node mcp/vault-export.js <vault>/doit-todos --install  # macOS: run --watch as a launchd agent
```

`--install` writes `~/Library/LaunchAgents/com.doit.vault-export.plist` and loads it, so the export stays current across reboots. It pins the `node` binary you ran it with, so run it again after switching Node versions. Errors go to `vault-export.log` in the data directory. To remove it, run `launchctl bootout gui/$(id -u)/com.doit.vault-export` and delete the plist.

Here's what lands in the folder:

| Path | What it holds |
|------|---------------|
| `doit-todos.md` | Every list with its in-progress, pending, and done counts |
| `<list>/<list>.md` | The list's index: in progress, pending (run queue first, then priority), done, and list notes |
| `<list>/<rank>-<slug>.md` | One open item. Frontmatter carries status, priority, type, rank, due, sequence, and links to its deps and its owed twin. The body is the item's notes |
| `<list>/done/<rank>-<slug>.md` | One finished item, same shape |
| `<list>/notes/<slug>.md` | One list-level note |

File names come from the item text, so editing an item's text renames its note. The exporter only rewrites notes whose content changed, and it only deletes notes it generated (the ones with a `doit_list` key in frontmatter), so anything else you drop in the folder stays put.

If your vault syncs to git, think about ignoring the export folder: item notes often hold commands, hostnames, and the odd credential pasted in while working.

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
