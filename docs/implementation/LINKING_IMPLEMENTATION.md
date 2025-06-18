# Todo-Note Linking Implementation

This document outlines the implementation of Obsidian-like `[[]]` linking syntax between todos and notes in do-it.nvim.

## Overview

The implementation enables linking todos to notes using:
1. Obsidian-like `[[note-title]]` syntax in todo text
2. A UI for selecting from available notes
3. Direct navigation from todos to their linked notes

## Implementation Details

### 1. Note Link Parsing (notes/state/init.lua)

Added functions to parse and handle note links:
- `parse_note_links()`: Extracts `[[note-title]]` patterns from text
- `find_note_by_title()`: Locates a note by title pattern
- `get_all_notes_titles()`: Lists available notes for link selection

### 2. Todo-Note Linking (todos/state/todos.lua)

Added functions to manage todo-note links:
- `process_note_links()`: Examines todo text for links and updates references
- Enhanced `add_todo()` and `edit_todo()` to process links automatically
- Added `link_todo_to_note()` and `unlink_todo_from_note()` for direct manipulation

### 3. UI Enhancement (ui/main_window.lua)

Added support for highlighting and navigating links:
- Enhanced rendering to highlight `[[]]` links
- Added `open_linked_note()` function for navigation
- Added UI indicators for linked notes

### 4. Note Selection UI (ui/todo_actions.lua)

Added UI for selecting notes when linking:
- Implemented `link_to_note()` function with selection UI
- Added ability to create new links or choose existing notes
- Integrated with main window keybindings

### 5. Styling (ui/highlights.lua)

Added styling for note links:
- Created `DoItNoteLink` highlight group
- Applied highlighting to `[[]]` syntax

### 6. Testing (tests/*.lua)

Added extensive tests for the new functionality:
- Unit tests for link parsing
- Tests for todo link processing
- Tests for note lookup functionality

### 7. Documentation

Created comprehensive documentation:
- Added `doc/doit_linking.txt` with usage and examples
- Added `NOTE_LINKING.md` with user-friendly explanation
- Added `LINKING_IMPLEMENTATION.md` with implementation details

## Key Files Modified

1. `/Users/bryan/dev/lua/do-it.nvim/lua/doit/modules/notes/state/init.lua`
   - Added link parsing and note finding functions

2. `/Users/bryan/dev/lua/do-it.nvim/lua/doit/modules/todos/state/todos.lua`
   - Added link processing and link management

3. `/Users/bryan/dev/lua/do-it.nvim/lua/doit/ui/main_window.lua`
   - Added navigation and rendering functions

4. `/Users/bryan/dev/lua/do-it.nvim/lua/doit/ui/todo_actions.lua`
   - Added note selection UI

5. `/Users/bryan/dev/lua/do-it.nvim/lua/doit/ui/highlights.lua`
   - Added link styling

6. `/Users/bryan/dev/lua/do-it.nvim/lua/doit/modules/todos/ui/todo_actions.lua`
   - Added module-level support for linking

## User Interaction Flow

1. **Creating Links**:
   - User can add `[[note-title]]` directly in todo text
   - User can press `n` on a todo to select from available notes
   - Links are automatically processed when adding/editing todos

2. **Navigating Links**:
   - User positions cursor on a linked todo
   - User presses `o` to open the linked note
   - The todo window closes and the notes window opens

3. **Visual Feedback**:
   - `[[]]` links are highlighted in green
   - Linked todos show a link icon (🔗)

## Future Enhancement Possibilities

1. Bidirectional linking with backlinks in notes
2. Sorting and filtering todos by linked notes
3. Multiple links per todo
4. Automatic note creation when linking to non-existent notes