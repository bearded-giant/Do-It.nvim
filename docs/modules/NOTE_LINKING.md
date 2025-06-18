# Note Linking in do-it.nvim

This document describes the note linking feature added to do-it.nvim, which allows linking todos and notes together using Obsidian-like `[[]]` syntax.

## Overview

The note linking feature allows you to:

1. Link todos to notes using Obsidian-like `[[note-title]]` syntax
2. Navigate directly from a todo to its linked note
3. Visually see which todos have linked notes
4. Select from available notes when creating links

## Usage

### Linking Todos to Notes

There are two ways to link a todo to a note:

1. **Using the link interface**:
   - Position the cursor on a todo
   - Press `n` to open the note linking interface
   - Select an existing note or choose to create a new link
   - If creating a new link, enter the note title

2. **Direct editing**:
   - When creating or editing a todo, include `[[note-title]]` anywhere in the text
   - The system will automatically create a link to a note with that title if it exists

### Navigating to Linked Notes

To navigate from a todo to its linked note:

1. Position the cursor on a todo with a link
2. Press `o` to open the linked note
3. The todo window will close and the notes window will open

### Identifying Linked Todos

Todos with linked notes are visually indicated in two ways:

1. The `[[note-title]]` syntax in the todo text is highlighted in green
2. A link icon (🔗) appears at the beginning of the todo line

## How It Works

### Link Detection

The system detects links in two ways:

1. **Direct links**: Todos can store a direct reference to a note ID
2. **Text-based links**: The `[[note-title]]` syntax is parsed from todo text

When a todo is created or edited, the system automatically scans for `[[]]` syntax and attempts to match it with existing notes.

### Configuration

The feature uses the following configuration options:

```lua
-- In config.lua
notes = {
    linked_icon = "🔗", -- Icon for todos linked to notes
},
keymaps = {
    open_linked_note = "o", -- Key to open a linked note
    -- The link_to_note function uses 'n' by default
}
```

## Examples

- Creating a todo with a link:
  ```
  Buy groceries [[Shopping List]]
  ```

- The link will be highlighted in the UI and clicking 'o' will open the "Shopping List" note if it exists

- Using the link interface:
  1. Create a todo: "Buy groceries"
  2. Press 'n' to open the linking interface
  3. Select "Shopping List" from existing notes or create a new link

## Future Enhancements

Potential future enhancements include:

1. Support for multiple links in a single todo
2. Bidirectional linking with note backlinks
3. Advanced filtering and search based on linked notes