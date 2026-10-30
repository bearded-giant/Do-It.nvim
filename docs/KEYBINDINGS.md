# Do-It.nvim Keybindings and Commands Reference

<!-- This file is auto-generated from lua/doit/help.lua - DO NOT EDIT DIRECTLY -->
<!-- To update: make update-help -->

## Commands

| Command | Description |
|---------|-------------|
| `:DoIt` | Open main todo window |
| `:DoItList` | Open quick todo list (floating) |
| `:DoItLists` | Manage multiple todo lists |
| `:DoItNotes` | Open notes window |

## Global Keymaps

| Key | Description |
|-----|-------------|
| `<leader>do` | Toggle main todo window |
| `<leader>dn` | Toggle notes window |
| `<leader>dl` | Toggle quick todo list |
| `<leader>dL` | Open list manager |

## Todo Window Keymaps

### Basic

| Key | Description |
|-----|-------------|
| `n` | New todo (in the Notes section: new note) |
| `<CR>` | Open todo text + details in the editor (note row: the note; Notes header: new note) |
| `s` | Start (in progress; one per list) |
| `x` | Complete |
| `X` | Revert to pending |
| `e` | Edit todo text (note row: edit the note) |
| `N` | Edit details in the editor |
| `P` | Set priority (critical/urgent/important) |
| `p` | New todo from the clipboard |
| `d` | Delete todo (or note, on a note row) |
| `D` | Delete all completed todos |
| `u` | Undo the last start/complete/revert or delete |
| `q/<Esc>` | Close window |
| `?` | Show help (with ALL keybindings) |

### Notes and editor

| Key | Description |
|-----|-------------|
| `g` | Notes picker (on a todo row: that todo's notes; n new linked note, l link, a all) |
| `gN` | In the todo editor: open that todo's notes |
| `q / :w` | In the editor: save and close / save |

### Organization

| Key | Description |
|-----|-------------|
| `K / J` | Move todo up / down within its group |
| `[ / ]` | Jump section down / up (priority groups, Mine/Claude, Notes) |
| `h` | Set or clear due date (YYYY-MM-DD) |
| `S` | Set or clear sequence (run order across priorities) |
| `t` | Filter by #tag |
| `c` | Clear the tag filter |
| `/` | Search and jump to a todo |
| `m` | Move todo to another list (s cycles view, m mine/claude, S flips list) |
| `l` | Switch list (links this tmux window) |
| `L` | List manager |
| `r` | Refresh from disk |

### Copy

| Key | Description |
|-----|-------------|
| `y` | Copy todo text (note row: note body) |
| `<C-y>` | Copy details without the footer (note row: note body) |
| `i` | Copy the item id (the doit MCP resolves it across lists) |
| `Y` | Copy the list name |

### nvim only

| Key | Description |
|-----|-------------|
| `a` | Add a child todo nested under the current one |
| `<Space>` | Cycle status (pending, in progress, done) |
| `H` | Due date from the calendar |
| `T / R` | Add / remove time estimation |
| `<leader>D` | Remove duplicate todos (confirms first, undoable with u) |

### Import/Export

| Key | Description |
|-----|-------------|
| `I` | Import todos from file |
| `E` | Export pending todos to markdown |
| `<leader>E` | Export todos to JSON file |
| `O` | Send todo to the Obsidian daily note |
| `B` | Back up all lists |

## List Manager Keymaps

| Key | Description |
|-----|-------------|
| `1-9, 0` | Quick select list by number |
| `j/k` | Navigate up/down |
| `Enter/Space` | Switch to selected list |
| `n` | Create new list |
| `d` | Delete selected list |
| `r` | Rename selected list |
| `i` | Import list from file |
| `e` | Export selected list |
| `s` | Cycle view: all -> mine -> claude (shared with tmux) |
| `m` | Toggle view straight between mine and claude |
| `S` | Flip selected list between mine and claude |
| `?` | Show full help |
| `q/Esc` | Close manager |

## Notes Window Keymaps

| Key | Description |
|-----|-------------|
| `m` | Switch between global/project mode |
| `q` | Close window |

## Features

- Multiple named todo lists with persistence
- Tag-based filtering with #hashtags
- Due dates with calendar integration
- Priority system with weights
- Time estimation tracking
- Project-specific or global notes
- Import/export for backup and sharing

## Customization

All keybindings can be customized in your config:

```lua
require("doit").setup({
  modules = {
    todos = {
      keymaps = {
        complete_todo = "x",
        toggle_todo = "<Space>",  -- Use space to toggle
        -- etc...
      }
    }
  }
})
```