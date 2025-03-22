# DoIt.nvim

[![Docker Tests](https://github.com/bryangrimes/doit/actions/workflows/run-tests.yml/badge.svg)](https://github.com/bryangrimes/doit/actions/workflows/run-tests.yml)

DoIt is a minimalist todo list manager for Neovim, designed with simplicity and efficiency in mind. It provides a clean, distraction-free interface to manage your tasks directly within Neovim.

DoIt is my personal way of how I want to track my tasks and todos. As a Principal Engineer, I have a lot of things to keep track of, and I wanted a simple way to do that without leaving my editor. I've tried a lot of todo list managers, and they all seem to be too much for me. I just want to keep track of what I need to do, and that's it. I don't need a bunch of bells and whistles. I just need to know what I need to do.

I also wanted a sandbox to play with Lua and some docker ideas around containerized Neovim plugin development and testing.  Oh also I'm dabbling some with Claude Code in this repo, to see how AI can help me learn a new-ish language...so that's something.   Anyway, here we are.

If you want to contribute or have any ideas, feel free to open an issue or make a PR. I don't know why you would, but hey, I'm not here to judge.  Cheers!

> This project is 100% built on top of [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas). DoIt is a fork with some heavy modifications for customizations for how I work, while maintaining the core functionality.

{...pics and video coming soon...}

## Features

- Manage todos in a simple and efficient way
- Categorize tasks with #tags
- Simple task management with clear visual feedback
- Persistent storage of your todos
- Adapts to your Neovim colorscheme
- Compatible with **Lazy.nvim** for effortless installation
- Relative timestamps showing when todos were created
- Import/Export of todo json for backups, obsidian integration...whatever you want

---

## Installation

### Prerequisites

- Neovim `>= 0.10.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) as your plugin manager

### Using Lazy.nvim

```lua
return {
    "bryangrimes/doit",
    config = function()
        require("doit").setup({
            -- optional configurations here...
        })
    end,
}
```

`:Lazy sync` to install and sync the plugin, or relaunch Neovim.

### Default Configuration

DoIt comes with sensible defaults that you can customize as you like.  Defaults:

```lua
{
    save_path = vim.fn.stdpath("data") .. "/doit_todos.json",  -- Data storage path
    timestamp = {
        enabled = true,         -- Show relative timestamps (e.g., @5m ago, @2h ago)
    },
    window = {
        width = 55,             -- Width of the floating window
        height = 20,            -- Height of the floating window
        border = 'rounded',     -- Border style
        position = 'center',    -- Window position: 'right', 'left', 'top', 'bottom', 'center',
                                    -- 'top-right', 'top-left', 'bottom-right', 'bottom-left'
        padding = {
            top = 1,
            bottom = 1,
            left = 2,
            right = 2,
        },
    },
    formatting = {              -- To-do formatting
        pending = {
            icon = "○",
            format = { "icon", "notes_icon", "text", "due_date", "ect" },
        },
        in_progress = {
            icon = "◐",
            format = { "icon", "text", "due_date", "ect" },
        },
        done = {
            icon = "✓",
            format = { "icon", "notes_icon", "text", "due_date", "ect" },
        },
    },
    quick_keys = true, 
    notes = {
        icon = "📓",
    },
    scratchpad = {
        syntax_highlight = "markdown",
    },
    keymaps = {
        toggle_window = "<leader>td",
        new_todo = "i",
        toggle_todo = "x",
        delete_todo = "d",
        delete_completed = "D",
        delete_confirmation = "<Y>",
        close_window = "q",
        undo_delete = "u",
        add_due_date = "H",
        remove_due_date = "r",
        toggle_help = "?",
        toggle_tags = "t",
        toggle_priority = "<Space>",
        clear_filter = "c",
        edit_todo = "e",
        edit_tag = "e",
        edit_priorities = "p",
        delete_tag = "d",
        search_todos = "/",
        add_time_estimation = "T",
        remove_time_estimation = "R",
        import_todos = "I",
        export_todos = "E",
        remove_duplicates = "<leader>D",
        open_todo_scratchpad = "<leader>p",
        reorder_todo = "r",
        move_todo_up = "k",
        move_todo_down = "j",
    },
    calendar = {
        language = "en",
        icon = "",
        keymaps = {
            previous_day = "h",
            next_day = "l",
            previous_week = "k",
            next_week = "j",
            previous_month = "H",
            next_month = "L",
            select_day = "<CR>",
            close_calendar = "q",
        },
    },
    priorities = {
        {
            name = "important",
            weight = 4,
        },
        {
            name = "urgent",
            weight = 2,
        },
    },
    priority_groups = {
        high = {
            members = { "important", "urgent" },
            color = nil,
            hl_group = "DiagnosticError",
        },
        medium = {
            members = { "important" },
            color = nil,
            hl_group = "DiagnosticWarn",
        },
        low = {
            members = { "urgent" },
            color = nil,
            hl_group = "DiagnosticInfo",
        },
    },
    hour_score_value = 1/8,
}
```

## Commands

DoIt provides several commands to get things done:

- `:doit` - Opens the main window
- `:doit add [text]` - Adds a new task
  - `-p, --priorities [list]` - Comma-separated list of priorities (e.g. "important,urgent")
- `:doit list` - Lists all todos with their indices and metadata
- `:doit set [index] [field] [value]` - Modifies todo properties
  - `priorities` - Set/update priorities (use "nil" to clear)
  - `ect` - Set estimated completion time (e.g. "30m", "2h", "1d", "0.5w")

---

## Keybinds

#### Main Window

| Key           | Action                        |
|--------------|------------------------------|
| `<leader>td` | Toggle todo window           |
| `i`          | Add new todo                 |
| `x`          | Toggle todo status           |
| `d`          | Delete current todo          |
| `D`          | Delete all completed todos   |
| `q`          | Close window                 |
| `H`          | Add due date                 |
| `r`          | Remove due date              |
| `T`          | Add time estimation          |
| `R`          | Remove time estimation       |
| `?`          | Toggle help window           |
| `t`          | Toggle tags window           |
| `c`          | Clear active tag filter      |
| `e`          | Edit todo                    |
| `p`          | Edit priorities              |
| `u`          | Undo delete                  |
| `/`          | Search todos                 |
| `I`          | Import todos                 |
| `E`          | Export todos                 |
| `<leader>D`  | Remove duplicates            |
| `<Space>`    | Toggle priority              |
| `<leader>p`  | Open todo scratchpad         |
| `r`          | Enter reordering mode        |

#### Reordering Mode

| Key    | Action                        |
|--------|------------------------------|
| `k`    | Move todo up                  |
| `j`    | Move todo down                |
| `r`    | Save and exit reordering mode |

#### Tags Window

| Key    | Action        |
|--------|--------------|
| `e`    | Edit tag     |
| `d`    | Delete tag   |
| `<CR>` | Filter by tag|
| `q`    | Close window |

#### Calendar Window

| Key    | Action              |
|--------|-------------------|
| `h`    | Previous day       |
| `l`    | Next day          |
| `k`    | Previous week     |
| `j`    | Next week         |
| `H`    | Previous month    |
| `L`    | Next month        |
| `<CR>` | Select date       |
| `q`    | Close calendar    |

---

## Roadmap...Sort of

- [x] Reorder Todos
- [ ] Active Todo to Top
- [ ] Named (and Multiple) Todo Lists
- [ ] Todo Categories View

---

## Acknowledgments

DoIt is FOR SURE based on [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas). Special thanks to him for creating the original plugin that inspired this fork.
