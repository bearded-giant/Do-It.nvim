-- Notes window UI for notes module
local api = vim.api
local M = {}

-- Module references
local config
local state
local core
local parent_module

-- Local state
local buf = nil
local win = nil

-- Initialize module
function M.setup(module)
    parent_module = module
    
    -- Get module components
    config = module.config
    state = module.state
    
    -- Try to get core UI utilities
    local success, core_module = pcall(require, "doit.core")
    if success and core_module and core_module.ui then
        core = core_module
    end
    
    return M
end

-- Create buffer for notes
function M.create_buf()
    -- Check if core UI is properly initialized with window module
    if core and core.ui and core.ui.window then
        buf = core.ui.create_buffer({
            filetype = config.markdown.syntax or "markdown",
            modifiable = true,
            bufhidden = "wipe"
        })
    else
        -- Fallback to direct nvim API
        buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_option(buf, "bufhidden", "wipe")
        api.nvim_buf_set_option(buf, "modifiable", true)
        api.nvim_buf_set_option(buf, "filetype", config.markdown.syntax or "markdown")
    end
    
    -- Apply markdown-specific options
    if config.markdown.highlight then
        -- Set conceallevel if enabled
        if config.markdown.conceallevel then
            api.nvim_buf_set_option(buf, "conceallevel", config.markdown.conceallevel)
        end
        
        -- Set concealcursor if enabled
        if config.markdown.concealcursor then
            api.nvim_buf_set_option(buf, "concealcursor", config.markdown.concealcursor)
        end
    end
    
    return buf
end

-- Create window for notes
function M.create_win()
    -- Get window config, supporting both new and legacy config paths
    local win_config = config.ui and config.ui.window or config.window
    
    local width, height
    
    -- Support both absolute and relative sizing
    if win_config.use_relative then
        width = math.floor(vim.o.columns * (win_config.relative_width or win_config.width))
        height = math.floor(vim.o.lines * (win_config.relative_height or win_config.height))
    else
        -- Use absolute values or fall back to relative calculation
        if type(win_config.width) == "number" and win_config.width > 1 then
            width = win_config.width
        else
            width = math.floor(vim.o.columns * win_config.width)
        end
        
        if type(win_config.height) == "number" and win_config.height > 1 then
            height = win_config.height
        else
            height = math.floor(vim.o.lines * win_config.height)
        end
    end
    
    -- Calculate position based on config
    local row, col
    if win_config.position == "center" then
        row = math.floor((vim.o.lines - height) / 2)
        col = math.floor((vim.o.columns - width) / 2)
    elseif win_config.position == "top-left" then
        row = 2
        col = 2
    elseif win_config.position == "top-right" then
        row = 2
        col = vim.o.columns - width - 2
    elseif win_config.position == "bottom-left" then
        row = vim.o.lines - height - 2
        col = 2
    elseif win_config.position == "bottom-right" then
        row = vim.o.lines - height - 2
        col = vim.o.columns - width - 2
    else
        -- Default to center
        row = math.floor((vim.o.lines - height) / 2)
        col = math.floor((vim.o.columns - width) / 2)
    end
    
    local mode_text = state.notes.current_mode == "global" and "Global Notes" or "Project Notes"
    
    local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = win_config.border,
        title = string.format("%s (%s)", win_config.title, mode_text),
        title_pos = win_config.title_pos,
    }
    
    if core and core.ui and core.ui.window then
        win = core.ui.create_float({
            buf = buf,
            width = win_config.width,
            height = win_config.height,
            border = win_config.border,
            title = string.format("%s (%s)", win_config.title, mode_text),
            title_pos = win_config.title_pos,
        })
    else
        win = api.nvim_open_win(buf, true, opts)
        
        -- Set window options
        api.nvim_win_set_option(win, "wrap", true)
        api.nvim_win_set_option(win, "linebreak", true)
        api.nvim_win_set_option(win, "number", true)
        
        -- Markdown-specific window options
        if config.markdown and config.markdown.highlight then
            -- Add spell checking which is useful for markdown
            api.nvim_win_set_option(win, "spell", true)
            -- Add list option which helps with automatic formatting
            api.nvim_win_set_option(win, "list", false) -- Turn off list chars which can affect markdown
            -- Set textwidth for auto-formatting
            api.nvim_win_set_option(win, "textwidth", 80)
        end
    end
    
    return win
end

-- Update window title
function M.update_title()
    if not win or not api.nvim_win_is_valid(win) then
        return
    end
    
    -- Get window config, supporting both new and legacy config paths
    local win_config = config.ui and config.ui.window or config.window
    
    local mode_text = state.notes.current_mode == "global" and "Global Notes" or "Project Notes"
    local opts = {
        title = string.format("%s (%s)", win_config.title, mode_text),
        title_pos = win_config.title_pos,
    }
    
    if core and core.ui and core.ui.window then
        core.ui.update_window_title(win, string.format("%s (%s)", win_config.title, mode_text), 
            { title_pos = win_config.title_pos })
    else
        api.nvim_win_set_config(win, opts)
    end
end

-- Close the notes window
function M.close_win()
    if win and api.nvim_win_is_valid(win) then
        -- Save notes before closing
        local content = M.get_notes_content()
        state.save_notes({ content = content })
        
        if core and core.ui and core.ui.window then
            core.ui.close_window(win)
        else
            api.nvim_win_close(win, true)
        end
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
    
    -- Add empty note template if there's no content
    if #lines == 0 then
        if config.markdown and config.markdown.highlight then
            -- Add a helpful markdown template
            table.insert(lines, "# " .. (state.notes.current_mode == "global" and "Global Notes" or "Project Notes"))
            table.insert(lines, "")
            table.insert(lines, "## Quick Reference")
            table.insert(lines, "")
            table.insert(lines, "- Use `#` for headers (# to ######)")
            table.insert(lines, "- Use `*text*` or `_text_` for *italic*")
            table.insert(lines, "- Use `**text**` or `__text__` for **bold**")
            table.insert(lines, "- Use `- item` for bullet lists")
            table.insert(lines, "- Use `1. item` for numbered lists")
            table.insert(lines, "- Use `[title](link)` for links")
            table.insert(lines, "- Use `![alt](image-url)` for images")
            table.insert(lines, "- Use ``` for code blocks")
            table.insert(lines, "")
            table.insert(lines, "## Notes")
            table.insert(lines, "")
        else
            table.insert(lines, "")
        end
    end
    
    -- Fill the buffer with content
    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Apply markdown syntax
    if config.markdown and config.markdown.highlight then
        -- If we have treesitter available, try to use it
        pcall(function()
            api.nvim_buf_set_option(buf, "syntax", "markdown")
        end)
    end
    
    -- Update the window title
    M.update_title()
    
    -- Position cursor at the end of the file for new notes
    if #lines > 0 and notes_data.content == "" then
        api.nvim_win_set_cursor(win, {#lines, 0})
    end
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
    local function set_keymap(key, callback, mode)
        if key then
            api.nvim_buf_set_keymap(buf, mode or "n", key, "", {
                noremap = true,
                silent = true,
                callback = callback
            })
        end
    end
    
    -- Switch between global and project notes
    set_keymap(config.keymaps.switch_mode, function()
        -- Save current notes before switching
        local content = M.get_notes_content()
        state.save_notes({ content = content })
        
        -- Switch mode and load new notes
        local new_notes = state.switch_mode()
        
        -- Render new notes
        M.render_notes(new_notes)
    end)
    
    -- Close window
    set_keymap(config.keymaps.close, function()
        M.close_win()
    end)
    
    -- Markdown specific keymaps
    if config.markdown and config.markdown.highlight then
        -- Format text - uses Neovim's built-in formatting
        set_keymap(config.keymaps.format, function()
            vim.cmd("normal! gqip") -- Format the current paragraph
        end)
        
        -- Headings
        set_keymap(config.keymaps.heading1, function()
            local cursor = api.nvim_win_get_cursor(win)
            local line_nr = cursor[1] - 1
            local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
            
            -- Remove any existing heading markers
            line = line:gsub("^%s*#+%s*", "")
            
            -- Add heading marker
            api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, {"# " .. line})
        end)
        
        set_keymap(config.keymaps.heading2, function()
            local cursor = api.nvim_win_get_cursor(win)
            local line_nr = cursor[1] - 1
            local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
            
            -- Remove any existing heading markers
            line = line:gsub("^%s*#+%s*", "")
            
            -- Add heading marker
            api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, {"## " .. line})
        end)
        
        set_keymap(config.keymaps.heading3, function()
            local cursor = api.nvim_win_get_cursor(win)
            local line_nr = cursor[1] - 1
            local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
            
            -- Remove any existing heading markers
            line = line:gsub("^%s*#+%s*", "")
            
            -- Add heading marker
            api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, {"### " .. line})
        end)
        
        -- Bold text
        set_keymap(config.keymaps.bold, function()
            -- Visual mode handling for bold
            local start_pos = vim.fn.getpos("'<")
            local end_pos = vim.fn.getpos("'>")
            
            -- Get the selected text
            local lines = api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
            if #lines == 0 then return end
            
            -- For single line selection
            if #lines == 1 then
                local selected_text = lines[1]:sub(start_pos[3], end_pos[3])
                local bold_text = "**" .. selected_text .. "**"
                
                -- Replace the selected text with bold text
                local new_line = lines[1]:sub(1, start_pos[3] - 1) .. bold_text .. lines[1]:sub(end_pos[3] + 1)
                api.nvim_buf_set_lines(buf, start_pos[2] - 1, start_pos[2], false, {new_line})
            end
        end, "v") -- Visual mode keymap
        
        -- Italic text
        set_keymap(config.keymaps.italic, function()
            -- Visual mode handling for italic
            local start_pos = vim.fn.getpos("'<")
            local end_pos = vim.fn.getpos("'>")
            
            -- Get the selected text
            local lines = api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
            if #lines == 0 then return end
            
            -- For single line selection
            if #lines == 1 then
                local selected_text = lines[1]:sub(start_pos[3], end_pos[3])
                local italic_text = "*" .. selected_text .. "*"
                
                -- Replace the selected text with italic text
                local new_line = lines[1]:sub(1, start_pos[3] - 1) .. italic_text .. lines[1]:sub(end_pos[3] + 1)
                api.nvim_buf_set_lines(buf, start_pos[2] - 1, start_pos[2], false, {new_line})
            end
        end, "v") -- Visual mode keymap
        
        -- Create link
        set_keymap(config.keymaps.link, function()
            vim.ui.input({ prompt = "Enter URL: " }, function(url)
                if not url or url == "" then return end
                
                vim.ui.input({ prompt = "Enter link text (optional): " }, function(text)
                    text = text or url
                    
                    local cursor = api.nvim_win_get_cursor(win)
                    local line_nr = cursor[1] - 1
                    local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
                    local col = cursor[2]
                    
                    local link_text = "[" .. text .. "](" .. url .. ")"
                    local new_line = line:sub(1, col) .. link_text .. line:sub(col + 1)
                    api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, {new_line})
                    
                    -- Position cursor after the inserted link
                    api.nvim_win_set_cursor(win, {cursor[1], col + #link_text})
                end)
            end)
        end)
        
        -- Insert list item
        set_keymap(config.keymaps.list_item, function()
            local cursor = api.nvim_win_get_cursor(win)
            local line_nr = cursor[1] - 1
            local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
            
            if line:match("^%s*$") then
                -- Empty line, just insert bullet
                api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, {"- "})
                api.nvim_win_set_cursor(win, {cursor[1], 2})
            else
                -- Go to next line and insert bullet
                api.nvim_buf_set_lines(buf, line_nr + 1, line_nr + 1, false, {"- "})
                api.nvim_win_set_cursor(win, {cursor[1] + 1, 2})
            end
        end)
    end
    
    -- Set up autocmd to save notes on buffer change and window close
    local save_augroup = api.nvim_create_augroup("DoItNotesSave", { clear = true })
    api.nvim_create_autocmd({"BufLeave", "WinLeave"}, {
        group = save_augroup,
        buffer = buf,
        callback = function()
            local content = M.get_notes_content()
            state.save_notes({ content = content })
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
    local notes = state.load_notes()
    
    -- Create buffer and window
    M.create_buf()
    M.create_win()
    
    -- Render notes
    M.render_notes(notes)
    
    -- Setup keymaps
    M.setup_keymaps()
end

return M
