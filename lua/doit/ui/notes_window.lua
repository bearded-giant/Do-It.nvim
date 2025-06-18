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
