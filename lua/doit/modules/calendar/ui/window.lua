-- Window management for calendar UI
local M = {}

-- Module reference
local calendar_module = nil
local win_id = nil
local buf_id = nil

-- Setup window module
function M.setup(module)
    calendar_module = module
    return M
end

-- Create calendar window
function M.create()
    -- Close existing window if any
    M.close()
    
    -- Create buffer
    buf_id = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf_id, "swapfile", false)
    vim.api.nvim_buf_set_option(buf_id, "filetype", "doit-calendar")
    vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
    
    -- Get window configuration
    local config = calendar_module.config.window
    local width = config.width or 80
    local height = config.height or 30
    
    -- Calculate position
    local ui = vim.api.nvim_list_uis()[1]
    local col, row
    
    if config.position == "center" then
        col = math.floor((ui.width - width) / 2)
        row = math.floor((ui.height - height) / 2)
    elseif config.position == "top-right" then
        col = ui.width - width - 2
        row = 2
    elseif config.position == "bottom-right" then
        col = ui.width - width - 2
        row = ui.height - height - 2
    else
        -- Default to center
        col = math.floor((ui.width - width) / 2)
        row = math.floor((ui.height - height) / 2)
    end
    
    -- Create window
    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        col = col,
        row = row,
        style = "minimal",
        border = config.border or "rounded",
        title = config.title or " Calendar ",
        title_pos = config.title_pos or "center"
    }
    
    win_id = vim.api.nvim_open_win(buf_id, true, win_opts)
    
    -- Set window options
    vim.api.nvim_win_set_option(win_id, "wrap", false)
    vim.api.nvim_win_set_option(win_id, "cursorline", true)
    vim.api.nvim_win_set_option(win_id, "number", false)
    vim.api.nvim_win_set_option(win_id, "relativenumber", false)
    
    -- Apply colors
    M.apply_highlights()
end

-- Close calendar window
function M.close()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, true)
    end
    
    if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
        vim.api.nvim_buf_delete(buf_id, { force = true })
    end
    
    win_id = nil
    buf_id = nil
end

-- Set window content
function M.set_content(lines)
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end
    
    vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

-- Get buffer ID
function M.get_buffer()
    return buf_id
end

-- Get window ID
function M.get_window()
    return win_id
end

-- Apply highlight groups
function M.apply_highlights()
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end
    
    local colors = calendar_module.config.colors
    
    -- Define highlight groups
    vim.cmd(string.format("highlight DoItCalendarBorder guifg=%s", colors.border or "Normal"))
    vim.cmd(string.format("highlight DoItCalendarTitle guifg=%s", colors.title or "Title"))
    vim.cmd(string.format("highlight DoItCalendarTime guifg=%s", colors.time_column or "Comment"))
    vim.cmd(string.format("highlight DoItCalendarEvent guifg=%s", colors.event or "Function"))
    vim.cmd(string.format("highlight DoItCalendarCurrentTime guifg=%s", colors.current_time or "DiagnosticWarn"))
    vim.cmd(string.format("highlight DoItCalendarHeader guifg=%s", colors.header or "Title"))
    vim.cmd(string.format("highlight DoItCalendarFooter guifg=%s", colors.footer or "Comment"))
end

-- Check if window is open
function M.is_open()
    return win_id and vim.api.nvim_win_is_valid(win_id)
end

return M