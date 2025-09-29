# Todos Module Documentation

The todos module provides comprehensive task management functionality within Neovim. This is the core module of DoIt.nvim, offering a complete GTD (Getting Things Done) workflow.

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

## Multiple Lists Support

The todos module supports managing multiple separate todo lists:

### Commands
- `:DoItLists` - Open the list manager
- `:DoItLists create <name>` - Create a new list
- `:DoItLists switch <name>` - Switch to a different list
- `:DoItLists delete <name>` - Delete a list

### List Manager Keys
- `<CR>` - Switch to selected list
- `n` - Create new list
- `d` - Delete selected list
- `r` - Rename selected list
- `q` - Close list manager

### Use Cases
- Separate personal and work tasks
- Project-specific todo lists
- Archive completed projects

## Tag System

Tags help organize and filter todos:

### Creating Tags
- Add tags directly in todo text: `#bug #urgent Fix login issue`
- Tags are automatically extracted and indexed

### Filtering by Tags
- Press `t` to open tag filter window
- Select multiple tags to filter
- Clear filters with `C`

### Popular Tags
- `#urgent` - High priority tasks
- `#bug` - Bug fixes
- `#feature` - New features
- `#docs` - Documentation tasks
- `#review` - Items needing review

## Priority System

Three priority levels help you focus on what's important:

- **High** (🔴) - Critical tasks
- **Medium** (🟡) - Normal priority
- **Low** (🟢) - Nice to have

Set priority:
1. Press `p` on a todo
2. Select priority level
3. Tasks auto-sort by priority

## Due Dates

Integrate deadlines with your workflow:

### Setting Due Dates
- Press `H` on a todo
- Enter date in natural format:
  - `tomorrow`
  - `next monday`
  - `2025-12-31`
  - `in 3 days`

### Due Date Display
- Overdue items show in red
- Due today shows in yellow
- Future dates show normally

## Import/Export

### Exporting
- `:Doit export` - Export current list
- Saves to `~/doit_export_<timestamp>.json`
- Includes all metadata

### Importing
- `:Doit import <file>` - Import from JSON file
- Merges with existing todos
- Preserves all properties

## Integration with Other Modules

### Notes Module
- Link todos to notes: `[[project-spec]]`
- Press `gf` on link to open note
- Bidirectional linking supported

### Calendar Module
- Due dates integrate with calendar view
- See todos in daily/weekly views
- Visual deadline tracking

## Tips and Tricks

1. **Quick Add**: Use `:Doit add` from anywhere
2. **Batch Operations**: Visual mode for multiple selections
3. **Smart Sorting**: Combines priority, due date, and creation time
4. **Search Operators**: Use `/tag:#bug status:pending`
5. **Keyboard Workflow**: Never touch the mouse

## Troubleshooting

### Common Issues

**Todos not saving:**
- Check save_path in configuration
- Ensure write permissions
- Look for error messages

**Keybindings not working:**
- Verify you're in the todo window
- Check for conflicts with other plugins
- Run `:checkhealth doit`

**Performance issues:**
- Limit number of todos per list
- Archive completed items regularly
- Disable animations if needed

## API

For plugin developers:

```lua
local todos = require("doit.modules.todos")

-- Get all todos
local all = todos.get_todos()

-- Add a new todo
todos.add_todo({
    text = "New task",
    priority = "high",
    tags = {"urgent", "bug"}
})

-- Update todo
todos.update_todo(index, {
    done = true,
    completed_at = os.time()
})
```

See [Plugin Development Guide](../development/PLUGIN_DEVELOPMENT.md) for more details.