# Do-It.nvim

[![Tests](https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml/badge.svg)](https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml)

Do-It.nvim is a minimalist to-do list manager for Neovim, designed with simplicity and efficiency in mind. It provides a clean, distraction-free interface to manage your tasks directly within Neovim.

Do-It.nvim is my personal way of how I want to track my tasks and to-dos. As a Principal Engineer, I have a lot of things to keep track of, and I wanted a simple way to do that without leaving my editor. I've tried a lot of to-do list managers, and they all seem to be too much for me. I just want to keep track of what I need to do, and that's it. I don't need a bunch of bells and whistles. I just need to know what I need to do.

I also wanted a sandbox to play with Lua and some docker ideas around containerized Neovim plugin development and testing.  Oh also I'm dabbling some with Claude Code in this repo, to see how AI can help me learn a new-ish language...so that's something.   Anyway, here we are.

If you want to contribute or have any ideas, feel free to open an issue or make a PR. I don't know why you would, but hey, I'm not here to judge.  Cheers!

> This project is 100% built on top of [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas). Do-It.nvim is a fork with some heavy modifications for customizations for how I work, while maintaining the core functionality.

{...pics and video coming soon...}

## Features

- Manage to-dos in a simple and efficient way
- Categorize tasks with #tags
- Simple task management with clear visual feedback
- Persistent storage of your to-dos
- Adapts to your Neovim colorscheme
- Compatible with **Lazy.nvim** for effortless installation
- Relative timestamps showing when to-dos were created
- Import/Export of to-do json for backups, obsidian integration...whatever you want
- To-do reordering with customizable keybindings
- In-progress (active) to-dos automatically float to the top of the list and sort by priority
- Quick list view of active to-dos with auto-refresh
- Lualine integration to show your active to-do in statusline
- Project-specific notes for documenting your work

---

## Installation

### Prerequisites

- Neovim `>= 0.10.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) as your plugin manager

### Using Lazy.nvim

```lua
return {
    "bearded-giant/do-it.nvim",
    config = function()
        require("doit").setup({
            -- optional configurations here...
        })
    end,
}
```

`:Lazy sync` to install and sync the plugin, or relaunch Neovim.

### Default Configuration

Do-It.nvim comes with sensible defaults that you can customize as you like.  Defaults:

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
    list_window = {
        width = 40,             -- Width of the active todos list window
        height = 10,            -- Height of the active todos list window
        position = 'bottom-right', -- Position of the active todos list window
    },
    lualine = {
        enabled = true,         -- Enable lualine integration
        max_length = 30,        -- Maximum length of the todo text in lualine
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
    project = {
        enabled = true,
        detection = {
            use_git = true,
            fallback_to_cwd = true,
        },
        storage = {
            path = vim.fn.stdpath("data") .. "/doit/projects",
        },
    },
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
    scratchpad = {
        syntax_highlight = "markdown",
    },
    keymaps = {
        toggle_window = "<leader>td",
        toggle_list_window = "<leader>dl",
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
        { name = "critical", weight = 16 },
        {
            name = "urgent",
            weight = 8,
        },
        {
            name = "important",
            weight = 4,
        },
    },
    priority_groups = {
        critical = {
            members = { "critical" },
            color = "#FF0000",
        },
        high = {
            members = { "urgent" },
            color = nil,
            hl_group = "DiagnosticError",
        },
        medium = {
            members = { "important" },
            color = nil,
            hl_group = "DiagnosticWarn",
        },
    },
    hour_score_value = 1/8,
}
```

## Commands

Do-It.nvim provides several commands to get things done:

- `:Doit` - Opens the main window
- `:Doit add [text]` - Adds a new to-do
  - `-p, --priority [name]` - Name of the priority to assign (e.g. "important" or "urgent")
- `:Doit list` - Lists all to-dos with their indices and metadata
- `:Doit set [index] [field] [value]` - Modifies to-do properties
  - `priorities` - Set/update priority (use "nil" to clear)
  - `ect` - Set estimated completion time (e.g. "30m", "2h", "1d", "0.5w")
- `:DoItList` - Toggle a floating window with active to-dos
- `:DoitNotes` - Toggle the project notes window

---

## Keybinds

#### Main Window

| Key           | Action                        |
|--------------|------------------------------|
| `<leader>td` | Toggle to-do window           |
| `<leader>dl` | Toggle active to-dos list     |
| `<leader>dn` | Toggle project notes window   |
| `i`          | Add new to-do                 |
| `x`          | Toggle status                 |
| `d`          | Delete current to-do          |
| `D`          | Delete all completed          |
| `q`          | Close window                  |
| `H`          | Add due date                  |
| `r`          | Remove due date               |
| `T`          | Add time estimation           |
| `R`          | Remove time estimation        |
| `?`          | Toggle help window            |
| `t`          | Toggle tags window            |
| `c`          | Clear active tag filter       |
| `e`          | Edit to-do                    |
| `p`          | Edit priorities               |
| `u`          | Undo delete                   |
| `/`          | Search to-dos                 |
| `I`          | Import to-dos                 |
| `E`          | Export to-dos                 |
| `<leader>D`  | Remove duplicates             |
| `<Space>`    | Toggle priority               |
| `<leader>p`  | Open scratchpad               |
| `r`          | Enter reordering mode         |

#### Reordering to-dos

| Key    | Action                        |
|--------|------------------------------|
| `k`    | Move to-do up                  |
| `j`    | Move to-do down                |
| `r`    | Save and exit reordering |

#### Tags Window

| Key    | Action        |
|--------|--------------|
| `e`    | Edit tag     |
| `d`    | Delete tag   |
| `<CR>` | Filter by tag|
| `q`    | Close window |

#### Notes Window

| Key    | Action                      |
|--------|----------------------------|
| `q`    | Close notes window         |
| `m`    | Switch between global/project|

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

## Lualine Integration

To add the active todo to your Lualine setup, add this to your Lualine configuration:

```lua
require("lualine").setup({
  sections = {
    lualine_c = {
      -- Your other components
      { require("doit").lualine.active_todo }
    }
  }
})
```

This will show your current active to-do in the Lualine status bar.

---

## Roadmap...Sort of

- [x] Reorder To-dos
- [x] Active To-do to Top
- [x] Quick list view of active to-dos
- [x] Lualine integration
- [x] Project-specific notes
- [ ] Named (and Multiple) To-do Lists
- [ ] To-do Categories View

---

## Project Notes

Do-it.nvim includes project notes functionality similar to maple.nvim:

- Project-specific notes based on Git repository or current directory
- Switch between global and project-specific notes with the 'm' key
- Store project documentation, ideas, and reference material 
- Uses Markdown syntax highlighting for better readability

Access project notes with `:DoitNotes` or use the configured keybinding (default: `<leader>dn`).

## Acknowledgments

Do-It.nvim is FOR SURE based on [Dooing](https://github.com/atiladefreitas/dooing) by [atiladefreitas](https://github.com/atiladefreitas). Special thanks to him for creating the original plugin that inspired this fork.

The project notes feature was inspired by maple.nvim's project notes functionality.