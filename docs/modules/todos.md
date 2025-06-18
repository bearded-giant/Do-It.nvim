# Todos Module

The todos module provides comprehensive task management functionality within Neovim.

## Features

- **Task Management**: Create, edit, delete, and organize to-dos
- **Priorities**: Assign priority levels (high, medium, low) to tasks
- **Due Dates**: Set deadlines with calendar integration
- **Tags**: Organize tasks with hashtag-based categories
- **Time Estimation**: Track estimated completion time
- **Search**: Filter tasks by content, tags, or status
- **Import/Export**: Backup and share task lists
- **Note Linking**: Link to project notes using `[[note-title]]` syntax

## Commands

- `:Doit` - Open the main todo window
- `:Doit add [text]` - Add a new todo
  - `-p, --priority [name]` - Set priority (e.g., "important", "urgent")
- `:Doit list` - List all todos with metadata
- `:Doit set [index] [field] [value]` - Modify todo properties
- `:DoItList` - Toggle floating window with active todos
- `:DoItLists` - Manage multiple todo lists

## Keybindings

| Key | Action |
|-----|--------|
| `i` | Add new todo |
| `x` | Toggle todo status |
| `d` | Delete current todo |
| `H` | Add due date |
| `t` | Toggle tags window |
| `p` | Edit priorities |
| `/` | Search todos |
| `r` | Enter reordering mode |
| `<Tab>` | Cycle through status states |
| `<CR>` | Edit todo text |

## Configuration

```lua
todos = {
    enabled = true,
    save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
    timestamp = { enabled = true },
    window = {
        width = 55,
        height = 20,
        border = "rounded",
        position = "center",
    },
    list_window = {
        width = 40,
        height = 10,
        position = "bottom-right",
    },
    formatting = {
        pending = { icon = "○" },
        in_progress = { icon = "◐" },
        done = { icon = "✓" },
    },
}
```

## Storage Format

Todos are stored in JSON format with the following structure:

```json
{
    "default": [
        {
            "text": "Task description",
            "status": "pending",
            "priority": "medium",
            "tags": ["work", "urgent"],
            "due_date": "2025-01-20",
            "estimated_completion_time": 120,
            "created_at": "2025-01-18T10:00:00Z",
            "updated_at": "2025-01-18T10:00:00Z"
        }
    ]
}
```