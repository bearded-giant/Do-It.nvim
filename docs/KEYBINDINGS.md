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

### Basic Operations

| Key | Description |
|-----|-------------|
| `<CR>` | Add new todo |
| `c` | Toggle todo status (pending→in-progress→done) |
| `X` | Revert todo to pending (not started) |
| `p` | Set/change priority (critical/urgent/important) |
| `d` | Delete current todo (or note, when on a note row) |
| `D` | Delete all completed todos |
| `u` | Undo last delete |
| `<leader>D` | Remove duplicate todos (confirms first, undoable with u) |
| `e` | Edit current todo (or note, when on a note row) |
| `gn` | Add a list note (scratch note in the Notes section) |
| `q/<Esc>` | Close window |
| `?` | Show help (with ALL keybindings) |

### Organization

| Key | Description |
|-----|-------------|
| `t` | Toggle tags window (filter by #tag) |
| `L` | List manager - switch lists, create new lists |
| `m` | Move current todo to another list |
| `f` | Clear active filter |
| `/` | Search todos |

### Advanced Features

| Key | Description |
|-----|-------------|
| `H` | Add/edit due date (calendar) |
| `r` | Reorder current todo (use j/k to move) |
| `T` | Add time estimation |
| `R` | Remove time estimation |
| `K` | View todo detail (full text + description) |
| `o` | Open linked note |
| `<leader>p` | Open scratchpad for todo |

### Import/Export

| Key | Description |
|-----|-------------|
| `I` | Import todos from file |
| `E` | Export pending todos to markdown |
| `<leader>E` | Export todos to JSON file |
| `O` | Export todo to Obsidian daily note |

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
        new_todo = "n",  -- Change '<CR>' to 'n' for legacy style
        toggle_todo = "<Space>",  -- Use space to toggle
        -- etc...
      }
    }
  }
})
```