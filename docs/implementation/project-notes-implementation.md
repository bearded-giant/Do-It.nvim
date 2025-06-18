# Project Notes Integration: Maple.nvim Features for Do-it.nvim

Based on analysis of both codebases, here's a phased implementation plan for integrating maple.nvim's project-based notes into do-it.nvim:

## Phase 1: Core Project Notes Support

**Key Features:**
1. Project-specific storage for notes based on git repo or directory
2. Global/Project mode switching
3. Basic project notes UI

**Implementation Steps:**

1. Extend do-it.nvim's configuration to support project notes:
   - Add project notes configuration options
   - Add note storage paths
   - Add UI configuration for project notes window

2. Create a dedicated notes storage module:
   - Project-specific note storage similar to maple.nvim's implementation
   - Load/save mechanics for project-specific notes

3. Build a basic notes UI:
   - Simple floating window for displaying and editing project notes
   - Mode switching (global/project) like maple.nvim

## Phase 2: Enhanced Integration

**Key Features:**
1. Deep integration with to-do items
2. Linking notes to specific to-dos
3. Rich text editing support
4. Notes search functionality

**Implementation Steps:**
1. Link notes to specific to-do items
2. Add search capabilities across notes
3. Implement rich text editing

## Phase 3: Advanced Features

**Key Features:**
1. Multiple note categories within projects
2. Notes tagging system 
3. Todo/Note cross-referencing
4. Advanced formatting options

## Implementation Detail for Phase 1

Here's the proposed implementation plan for Phase 1:

1. **Configuration Updates:**

```lua
-- Add to config.lua defaults:
project = {
    enabled = true,
    detection = {
        use_git = true,
        fallback_to_cwd = true,
    },
    storage = {
        path = vim.fn.stdpath("data") .. "/doit/projects",
    },
},
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

2. **Create Notes Module Structure:**

```
lua/doit/
├── state/
│   ├── project.lua (enhance existing)
│   └── notes.lua (new)
└── ui/
    └── notes_window.lua (new)
```

3. **Enhance Project Module:**

The existing `project.lua` already has nice functionality for project detection, but we need to extend it to support notes.

4. **Create Notes State Module:**

Create a new `notes.lua` module in the state directory to handle loading, saving, and managing project-specific notes.

5. **Create Notes UI Module:**

Create a new UI module for rendering and interacting with notes in a floating window.

6. **Command Interface:**

Add new commands like `:DoItNotes` to toggle the notes window.

## Code Differences from maple.nvim

1. **Storage Approach:**
   - Maple uses plenary.path for file operations
   - Do-it uses Lua's io module directly
   - We should adapt maple's approach to match do-it's style

2. **UI Implementation:**
   - Do-it has a more sophisticated window system with padding, positioning, etc.
   - We should leverage do-it's existing UI patterns rather than copying maple's

3. **Project Detection:**
   - Do-it already has project detection code in the unused project.lua file
   - We can enhance and activate this functionality

## Example Implementation of Key Components

1. **Notes State Module** (lua/doit/state/notes.lua):

```lua
local M = {}
local config = require("doit.config")

-- Initialize with defaults
M.notes = {
    global = { content = "" },
    project = {},
    current_mode = "project",
}

-- Get current project path from project module
local function get_project_identifier()
    return require("doit.state").get_project_identifier()
end

-- Get storage path based on mode
function M.get_storage_path(is_global)
    local base_path = config.options.notes.storage_path or vim.fn.stdpath("data") .. "/doit/notes"
    
    -- Create the directory if it doesn't exist
    local mkdir_cmd = vim.fn.has("win32") == 1 and "mkdir" or "mkdir -p"
    vim.fn.system(mkdir_cmd .. " " .. vim.fn.shellescape(base_path))
    
    if not is_global and config.options.notes.mode == "project" then
        local project_id = get_project_identifier()
        if project_id then
            local hash = vim.fn.sha256(project_id)
            return base_path .. "/project-" .. string.sub(hash, 1, 10) .. ".json"
        end
    end
    
    return base_path .. "/global.json"
end

-- Load notes from storage
function M.load_notes()
    local is_global = M.notes.current_mode == "global"
    local file_path = M.get_storage_path(is_global)
    local result = { content = "" }
    
    local success, f = pcall(io.open, file_path, "r")
    if success and f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local status, notes_data = pcall(vim.fn.json_decode, content)
            if status and notes_data and notes_data.content then
                result = notes_data
            end
        end
    end
    
    if is_global then
        M.notes.global = result
    else
        local project_id = get_project_identifier()
        if project_id then
            M.notes.project[project_id] = result
        end
    end
    
    return result
end

-- Save notes to storage
function M.save_notes(notes_content)
    if not notes_content then
        vim.notify("Invalid notes data provided", vim.log.levels.ERROR)
        return
    end
    
    local is_global = M.notes.current_mode == "global"
    local file_path = M.get_storage_path(is_global)
    
    local success, f = pcall(io.open, file_path, "w")
    if success and f then
        local status, json_content = pcall(vim.fn.json_encode, notes_content)
        if status then
            f:write(json_content)
            f:close()
            
            if is_global then
                M.notes.global = notes_content
            else
                local project_id = get_project_identifier()
                if project_id then
                    M.notes.project[project_id] = notes_content
                end
            end
        else
            vim.notify("Error encoding notes data", vim.log.levels.ERROR)
            f:close()
        end
    else
        vim.notify("Failed to save notes to file", vim.log.levels.ERROR)
    end
end

-- Switch between global and project notes
function M.switch_mode()
    -- Toggle mode
    if M.notes.current_mode == "global" then
        M.notes.current_mode = "project"
    else
        M.notes.current_mode = "global"
    end
    
    -- Load notes for the new mode
    return M.load_notes()
end

-- Get current notes
function M.get_current_notes()
    if M.notes.current_mode == "global" then
        return M.notes.global
    else
        local project_id = get_project_identifier()
        if project_id and M.notes.project[project_id] then
            return M.notes.project[project_id]
        end
        -- Load from disk if not in memory
        return M.load_notes()
    end
end

return M
```

2. **Notes Window UI Module** (lua/doit/ui/notes_window.lua):

```lua
local api = vim.api
local M = {}
local config = require("doit.config")
local state = require("doit.state")
local notes_state = require("doit.state.notes")

local buf = nil
local win = nil

-- Create buffer for notes
function M.create_buf()
    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_option(buf, "filetype", "markdown")
    return buf
end

-- Create window for notes
function M.create_win()
    local width = math.floor(vim.o.columns * config.options.notes.window.width)
    local height = math.floor(vim.o.lines * config.options.notes.window.height)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    
    local mode_text = notes_state.notes.current_mode == "global" and "Global Notes" or "Project Notes"
    
    local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = config.options.notes.window.border,
        title = string.format("%s (%s)", config.options.notes.window.title, mode_text),
        title_pos = config.options.notes.window.title_pos,
    }
    
    win = api.nvim_open_win(buf, true, opts)
    
    -- Set window options
    api.nvim_win_set_option(win, "wrap", true)
    api.nvim_win_set_option(win, "linebreak", true)
    api.nvim_win_set_option(win, "number", true)
    
    return win
end

-- Update window title
function M.update_title()
    if not win or not api.nvim_win_is_valid(win) then
        return
    end
    
    local mode_text = notes_state.notes.current_mode == "global" and "Global Notes" or "Project Notes"
    local opts = {
        title = string.format("%s (%s)", config.options.notes.window.title, mode_text),
        title_pos = config.options.notes.window.title_pos,
    }
    api.nvim_win_set_config(win, opts)
end

-- Close the notes window
function M.close_win()
    if win and api.nvim_win_is_valid(win) then
        -- Save notes before closing
        local content = M.get_notes_content()
        notes_state.save_notes({ content = content })
        api.nvim_win_close(win, true)
        win = nil
    end
end

-- Render notes in the window
function M.render_notes(notes_data)
    if not buf or not win then return end
    
    local content = notes_data.content or ""
    local lines = {}
    
    -- Split content into lines
    if content and content ~= "" then
        for line in content:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end
    end
    
    if #lines == 0 then
        table.insert(lines, "")
    end
    
    -- Fill the buffer with content
    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Update the window title
    M.update_title()
end

-- Get notes content from buffer
function M.get_notes_content()
    if not buf or not win or not api.nvim_win_is_valid(win) then
        return ""
    end
    
    -- Get all lines from buffer
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    
    -- Remove trailing empty lines
    while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
    end
    
    return table.concat(lines, "\n")
end

-- Setup keymaps for notes window
function M.setup_keymaps()
    if not buf then return end
    
    -- Set up a basic key mapping function
    local function set_keymap(key, callback)
        if key then
            api.nvim_buf_set_keymap(buf, "n", key, "", {
                noremap = true,
                silent = true,
                callback = callback
            })
        end
    end
    
    -- Switch between global and project notes
    set_keymap(config.options.notes.keymaps.switch_mode, function()
        -- Save current notes before switching
        local content = M.get_notes_content()
        notes_state.save_notes({ content = content })
        
        -- Switch mode and load new notes
        local new_notes = notes_state.switch_mode()
        
        -- Render new notes
        M.render_notes(new_notes)
    end)
    
    -- Close window
    set_keymap(config.options.notes.keymaps.close, function()
        M.close_win()
    end)
    
    -- Set up autocmd to save notes on buffer change and window close
    local save_augroup = api.nvim_create_augroup("DoItNotesSave", { clear = true })
    api.nvim_create_autocmd({"BufLeave", "WinLeave"}, {
        group = save_augroup,
        buffer = buf,
        callback = function()
            local content = M.get_notes_content()
            notes_state.save_notes({ content = content })
        end
    })
end

-- Toggle notes window
function M.toggle_notes_window()
    -- If window is already open, close it
    if win and api.nvim_win_is_valid(win) then
        M.close_win()
        return
    end
    
    -- Load notes
    local notes = notes_state.load_notes()
    
    -- Create buffer and window
    M.create_buf()
    M.create_win()
    
    -- Render notes
    M.render_notes(notes)
    
    -- Setup keymaps
    M.setup_keymaps()
end

return M
```

3. **Integration with main module** (update in lua/doit/init.lua):

```lua
-- Add to existing requires:
local notes_window = require("doit.ui.notes_window")

-- Add to setup function:
if config.options.notes and config.options.notes.enabled then
    vim.api.nvim_create_user_command("DoItNotes", function()
        notes_window.toggle_notes_window()
    end, {
        desc = "Toggle notes window",
    })
    
    if config.options.notes.keymaps.toggle then
        vim.keymap.set("n", config.options.notes.keymaps.toggle, function()
            notes_window.toggle_notes_window()
        end, { desc = "Toggle Notes Window" })
    end
end
```

## Conclusion

The integration of maple.nvim's project notes into do-it.nvim would significantly enhance its capabilities while maintaining a cohesive user experience. The proposed phased approach allows for incremental implementation, starting with basic functionality and building toward more advanced features.

Phase 1 provides a solid foundation for project notes without disrupting existing todo functionality, while Phases 2 and 3 would enable more powerful integrations between todos and notes.
