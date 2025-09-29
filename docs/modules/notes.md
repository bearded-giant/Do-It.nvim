# Notes Module Documentation

> **Work in Progress**: The Notes module is actively being developed. Some features may change or be incomplete.

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

## Usage Patterns

### Project Documentation
Use project notes for:
- Architecture decisions
- Local setup instructions
- Project-specific TODOs
- Meeting notes
- Debug logs and findings

### Global Knowledge Base
Use global notes for:
- Code snippets
- Common patterns
- Learning notes
- Cross-project references
- Personal documentation

## Note Organization

Organize notes with markdown headers:
```markdown
# Project Overview

## Architecture
Details about the system design...

## Setup Instructions
1. Install dependencies
2. Configure environment

## Meeting Notes
### 2025-01-20 - Sprint Planning
- Discussed feature priorities
```

## Planned Features (Coming Soon)

These features are in development:

- **Note Templates**: Predefined templates for common note types
- **Search Functionality**: Full-text search across all notes
- **Note Linking**: Bidirectional links between notes
- **Export Options**: Export notes to various formats
- **Version Control**: Track changes and history
- **Tags and Categories**: Organize notes with metadata
- **Quick Capture**: Capture notes from anywhere with hotkeys

## Tips and Tricks

1. **Quick Access**: Map `:DoItNotes` to a convenient key
2. **Markdown Preview**: Use a markdown preview plugin alongside
3. **Templates**: Create your own templates and copy them
4. **Organization**: Use consistent header structure
5. **Linking**: Create a table of contents with links

## Troubleshooting

### Notes Not Saving
- Check storage_path permissions
- Ensure directory exists
- Look for error messages in `:messages`

### Window Not Opening
- Verify notes module is enabled
- Check for keybinding conflicts
- Run `:checkhealth doit`

### Project Detection Issues
- Ensure you're in a Git repository
- Check Git configuration
- Try global mode as fallback

## Configuration Examples

### Minimal Setup
```lua
notes = {
    enabled = true,
}
```

### Custom Storage Location
```lua
notes = {
    enabled = true,
    storage_path = "~/Documents/nvim-notes",
}
```

### Larger Window
```lua
notes = {
    enabled = true,
    window = {
        width = 0.8,
        height = 0.8,
    }
}
```

## API (For Developers)

```lua
local notes = require("doit.modules.notes")

-- Get current note content
local content = notes.get_content()

-- Set note content
notes.set_content("# New Content\n\nHello world")

-- Switch to global mode
notes.set_mode("global")

-- Open specific note
notes.open_note("project-name")
```

## Roadmap

The Notes module is being actively developed. Priority features:

1. **Phase 1** (Current)
   - Basic note creation and editing
   - Project/global mode switching
   - Auto-save functionality

2. **Phase 2** (Next)
   - Note templates
   - Search functionality
   - Better linking system

3. **Phase 3** (Future)
   - Version control integration
   - Export capabilities
   - Advanced organization features

## Contributing

We welcome contributions to the Notes module! Areas where help is needed:

- Template system implementation
- Search functionality
- UI/UX improvements
- Documentation and examples
- Bug fixes and testing

See [Contributing Guide](../../CONTRIBUTING.md) for details.