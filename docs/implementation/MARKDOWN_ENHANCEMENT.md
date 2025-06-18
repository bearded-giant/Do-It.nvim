# Markdown Enhancement for Notes Module

This update adds comprehensive Markdown support to the notes module, making it more user-friendly and feature-rich for note-taking.

## New Features

1. **Markdown Configuration**
   - Added dedicated markdown configuration section in the notes module config
   - Configurable syntax highlighting and concealing options
   - Support for Markdown extensions

2. **Enhanced Buffer and Window Setup**
   - Proper Markdown filetype association
   - Concealing of Markdown syntax (hides formatting markers for cleaner reading)
   - Window options optimized for Markdown editing (wrap, spell checking, etc.)

3. **Rich Markdown Editing Tools**
   - Added keyboard shortcuts for common Markdown formatting:
     - Headings (H1, H2, H3)
     - Text formatting (bold, italic)
     - Links
     - Lists
     - Text formatting

4. **Empty Note Template**
   - New notes now include a helpful Markdown reference template
   - Shows common Markdown syntax for quick reference
   - Makes the notes interface more beginner-friendly

5. **Improved Syntax Highlighting**
   - Better syntax highlighting for Markdown elements
   - Support for code blocks, headings, lists, etc.

## Configuration Options

```lua
markdown = {
    highlight = true,          -- Enable or disable markdown highlighting
    syntax = "markdown",       -- Syntax to use for the notes buffer
    conceallevel = 2,          -- Enable concealing of formatting markers
    concealcursor = "nc",      -- Modes in which concealing is active when cursor is on line
    extensions = true,         -- Enable markdown extensions like tables, etc.
},
```

## Default Keymaps

```lua
keymaps = {
    toggle = "<leader>dn",     -- Toggle notes window
    close = "q",               -- Close notes window
    switch_mode = "m",         -- Switch between global and project notes
    format = "gq",             -- Format paragraph
    heading1 = "<leader>1",    -- Insert/convert to H1
    heading2 = "<leader>2",    -- Insert/convert to H2
    heading3 = "<leader>3",    -- Insert/convert to H3
    bold = "<leader>b",        -- Make text bold (visual mode)
    italic = "<leader>i",      -- Make text italic (visual mode)
    link = "<leader>l",        -- Insert link
    list_item = "<leader>-",   -- Insert list item
},
```

## Implementation Details

1. Added Markdown-specific options to buffer creation:
   - Filetype association
   - Concealing of Markdown syntax markers
   - Window options optimized for Markdown editing

2. Enhanced the render_notes function to:
   - Show a helpful Markdown template for new notes
   - Apply appropriate syntax highlighting
   - Position cursor at end of template for immediate editing

3. Added extensive keymaps for Markdown editing:
   - Headings (convert current line to heading)
   - Text formatting (bold/italic for selected text)
   - Interactive link creation
   - List item insertion

These enhancements make the notes module much more powerful and user-friendly, especially for users who are familiar with Markdown.