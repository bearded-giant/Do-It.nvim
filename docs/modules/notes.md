# Notes Module V2

Multi-note management with a picker, per-note CRUD, sorting, and scoped storage.

## What Changed in V2

- **Multiple notes per scope** instead of one global + one project note
- **Picker window** as the entry point (lists all notes for the active scope)
- **Create / delete** notes with title prompt and confirmation
- **Sort cycling** (newest, title a-z, oldest)
- **Search filter** via `vim.ui.input`
- **Editor returns to picker** on close instead of dismissing entirely
- **Data model**: `content` renamed to `body`, notes stored as JSON arrays
- **Migration**: existing single-note files are auto-converted on first load

## Commands

- `:DoItNotes` - Toggle the notes picker

## Keybindings

### Picker

| Key | Action |
|-----|--------|
| `<leader>dn` | Toggle picker |
| `Enter` | Open selected note in editor |
| `n` | Create new note (prompts for title) |
| `d` | Delete selected note (confirms y/N) |
| `m` | Toggle scope (global / project) |
| `s` | Cycle sort order |
| `/` | Filter notes by title |
| `q` | Close picker |

### Editor

| Key | Action |
|-----|--------|
| `q` | Save and return to picker |
| `gq` | Format paragraph |
| `<leader>1` | Set heading level 1 |
| `<leader>2` | Set heading level 2 |
| `<leader>3` | Set heading level 3 |
| `<leader>b` | Bold (visual mode) |
| `<leader>i` | Italic (visual mode) |
| `<leader>l` | Insert link |
| `<leader>-` | Insert list item |

## Configuration

```lua
notes = {
    enabled = true,
    ui = {
        window = {
            position = "center",
            border = "rounded",
            title = " Notes ",
            title_pos = "center",
            relative_width = 0.6,
            relative_height = 0.6,
            use_relative = true,
        },
    },
    storage = {
        path = vim.fn.stdpath("data") .. "/doit/notes",
        mode = "project", -- "global" or "project" (initial scope on open)
    },
    markdown = {
        highlight = true,
        syntax = "markdown",
        conceallevel = 2,
    },
    keymaps = {
        toggle = "<leader>dn",
        picker = {
            open = "<CR>",
            new = "n",
            delete = "d",
            scope_toggle = "m",
            sort = "s",
            search = "/",
            close = "q",
        },
        editor = {
            close = "q",
            format = "gq",
            heading1 = "<leader>1",
            heading2 = "<leader>2",
            heading3 = "<leader>3",
            bold = "<leader>b",
            italic = "<leader>i",
            link = "<leader>l",
            list_item = "<leader>-",
        },
    },
}
```

## Storage

Notes are stored as JSON arrays per scope:

- **Global**: `~/.local/share/nvim/doit/notes/global.json`
- **Project**: `~/.local/share/nvim/doit/notes/project-{hash}.json`

The project hash is derived from the git root or current working directory.

### Note Object

```json
{
    "id": "1769643796_2123853",
    "title": "some title",
    "body": "",
    "created_at": 1769643796,
    "updated_at": 1769643796,
    "scope": "global",
    "project_id": null
}
```

### Migration from V1

On first load, if a JSON file contains a single object (V1 format), it is automatically wrapped into an array and the `content` field is renamed to `body`. No manual action required.

## UI Flow

### Picker (entry point)

```
 Notes [Global]
--------------------------------------------------
 n: New   d: Delete   /: Search   m: Scope   s: Sort (date newest)
--------------------------------------------------
  Meeting notes                        2d ago
  API design decisions                 1w ago
  Deploy checklist                     3w ago
--------------------------------------------------
```

### Editor

Opened from the picker when selecting a note. Shows the note body as editable markdown. The window title displays `Note: {title}`. Pressing `q` saves and returns to the picker.

Auto-saves on `BufLeave` / `WinLeave` and closes on `FocusLost` (prevents floating window persistence when switching tmux panes).

## Scope Switching

Press `m` in the picker to toggle between Global and Project scopes. The `storage.mode` config option sets which scope is active on first open, but both scopes are always available via toggle. Each scope maintains its own JSON file.

## Troubleshooting

### Notes not saving
- Check storage path permissions
- Ensure the directory exists (created automatically)
- Run `:messages` for errors

### Same notes in different projects
- Verify you are opening neovim from different directories
- Project identity is based on git root or cwd

### Floating window persists across tmux panes
- Add `set -g focus-events on` to your `.tmux.conf`
- The picker and editor close on `FocusLost`
