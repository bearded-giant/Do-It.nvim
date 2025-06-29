local M = {}

function M.create_buffer(opts)
    opts = opts or {}
    
    local buf = vim.api.nvim_create_buf(false, true)
    
    if opts.filetype then
        vim.api.nvim_buf_set_option(buf, "filetype", opts.filetype)
    end
    
    vim.api.nvim_buf_set_option(buf, "bufhidden", opts.bufhidden or "wipe")
    vim.api.nvim_buf_set_option(buf, "modifiable", opts.modifiable ~= false)
    
    return buf
end

function M.calculate_position(width, height, position)
    local pos = {
        row = 0,
        col = 0,
    }
    
    local editor_width = vim.o.columns
    local editor_height = vim.o.lines
    
    if width <= 1 then
        width = math.floor(editor_width * width)
    end
    
    if height <= 1 then
        height = math.floor(editor_height * height)
    end
    
    if position == "center" then
        pos.row = math.floor((editor_height - height) / 2)
        pos.col = math.floor((editor_width - width) / 2)
    elseif position == "top" then
        pos.row = 1
        pos.col = math.floor((editor_width - width) / 2)
    elseif position == "bottom" then
        pos.row = editor_height - height - 2
        pos.col = math.floor((editor_width - width) / 2)
    elseif position == "left" then
        pos.row = math.floor((editor_height - height) / 2)
        pos.col = 1
    elseif position == "right" then
        pos.row = math.floor((editor_height - height) / 2)
        pos.col = editor_width - width - 2
    elseif position == "top-left" then
        pos.row = 1
        pos.col = 1
    elseif position == "top-right" then
        pos.row = 1
        pos.col = editor_width - width - 2
    elseif position == "bottom-left" then
        pos.row = editor_height - height - 2
        pos.col = 1
    elseif position == "bottom-right" then
        pos.row = editor_height - height - 2
        pos.col = editor_width - width - 2
    end
    
    return {
        width = width,
        height = height,
        row = pos.row,
        col = pos.col,
    }
end

function M.create_float(opts)
    opts = opts or {}
    
    local buf = opts.buf or M.create_buffer(opts)
    
    local width = opts.width or 50
    local height = opts.height or 15
    local position = opts.position or "center"
    
    local pos = M.calculate_position(width, height, position)
    
    local win_opts = {
        relative = opts.relative or "editor",
        width = pos.width,
        height = pos.height,
        row = pos.row,
        col = pos.col,
        style = opts.style or "minimal",
        border = opts.border or "rounded",
    }
    
    if opts.title then
        win_opts.title = opts.title
        win_opts.title_pos = opts.title_pos or "center"
    end
    
    local win = vim.api.nvim_open_win(buf, opts.focus ~= false, win_opts)
    
    if opts.winblend then
        vim.api.nvim_win_set_option(win, "winblend", opts.winblend)
    end
    
    if opts.wrap ~= false then
        vim.api.nvim_win_set_option(win, "wrap", true)
    end
    
    if opts.cursorline ~= false then
        vim.api.nvim_win_set_option(win, "cursorline", true)
    end
    
    return win, buf
end

function M.close(win)
    if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
        return true
    end
    return false
end

function M.update_config(win, opts)
    if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_config(win, opts)
        return true
    end
    return false
end

function M.update_title(win, title, opts)
    if win and vim.api.nvim_win_is_valid(win) then
        local win_opts = {
            title = title,
            title_pos = opts and opts.title_pos or "center",
        }
        vim.api.nvim_win_set_config(win, win_opts)
        return true
    end
    return false
end

function M.is_valid(win)
    return win and vim.api.nvim_win_is_valid(win)
end

return M