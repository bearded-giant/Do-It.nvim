# Obsidian-Sync Module for DoIt.nvim

Integration module that bridges DoIt.nvim todos with Obsidian.nvim markdown notes.

## Features

- **Import todos from Obsidian notes** - Extract checkbox items from markdown files
- **Sync completion status** - When marking todos complete in DoIt, updates Obsidian checkboxes
- **Navigation** - Jump between DoIt todos and their source in Obsidian
- **Smart list assignment** - Automatically assigns todos to lists based on file location or tags
- **Non-invasive markers** - Uses HTML comments to track references

## Setup

In your DoIt configuration:

```lua
require("doit").setup({
    modules = {
        ["obsidian-sync"] = {
            vault_path = "~/Recharge-Notes",
            auto_import_on_open = false,  -- Auto-import when opening daily notes
            sync_completions = true,       -- Sync completion status back to Obsidian
            default_list = "obsidian",    -- Default list for imported todos
            list_mapping = {
                daily = "daily",
                inbox = "inbox",
                projects = "projects"
            }
        }
    }
})
```

## Commands

- `:DoItImportBuffer` - Import todos from current Obsidian buffer
- `:DoItImportToday` - Import todos from today's daily note
- `:DoItGotoSource` - Jump to Obsidian source of current todo
- `:DoItSyncStatus` - Show sync status information

## Keymaps

In Obsidian buffers:
- `<leader>di` - Import todos to DoIt
- `<leader>dt` - Send current line todo to DoIt

In DoIt window:
- `gO` - Go to Obsidian source (when available)

## How It Works

1. **Import**: Scans markdown for checkbox lines (`- [ ] Task text`)
2. **Track**: Adds HTML comment markers (`<!-- doit:id -->`) to track references
3. **Sync**: When toggling in DoIt, updates checkbox state in Obsidian
4. **Navigate**: Jump between systems using stored buffer/line references

## Daily Workflow

```vim
:ObsidianToday        " Create/open today's daily note
:DoItImportBuffer     " Import unchecked todos
:DoIt                 " Open DoIt window
```

## Notes

- References are session-based (not persisted between Neovim restarts)
- Only unchecked items are imported
- Completed items sync back to source files
- Works with any Obsidian vault structure