# Notes Module

The notes module provides project-specific and global note-taking capabilities within Neovim.

## Features

- **Project-Specific Notes**: Automatically associate notes with Git repositories
- **Global Notes**: System-wide notes accessible from any project
- **Markdown Support**: Full syntax highlighting and formatting
- **Floating Window**: Non-intrusive interface that doesn't disrupt your workflow
- **Auto-Save**: Automatically saves changes as you type
- **Todo Integration**: Link notes from todo items using `[[note-title]]` syntax

## Commands

- `:DoItNotes` - Toggle the notes window
- `:DoItNotes global` - Open global notes
- `:DoItNotes project` - Open project-specific notes

## Keybindings

| Key | Action |
|-----|--------|
| `<leader>dn` | Toggle notes window |
| `q` | Close notes window |
| `m` | Switch between global/project mode |

## Configuration

```lua
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
}
```

## Storage

Notes are stored as markdown files:
- **Project Notes**: `{storage_path}/projects/{project_id}.md`
- **Global Notes**: `{storage_path}/global.md`

The project ID is generated from the Git repository path or current working directory.

## Integration with Todos

You can link to notes from todo items using the wiki-style syntax:
- `[[note-title]]` - Links to a specific note
- Notes can be opened directly from the todo interface