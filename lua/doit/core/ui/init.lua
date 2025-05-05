-- Core UI utilities for doit.nvim
local M = {}

-- Initialize UI utilities
function M.setup()
    M.window = require("doit.core.ui.window")
    M.theme = require("doit.core.ui.theme")
    return M
end

-- Create a floating window
function M.create_float(opts)
    return M.window.create_float(opts)
end

-- Close a window
function M.close_window(win)
    return M.window.close(win)
end

-- Update window title
function M.update_window_title(win, title, opts)
    return M.window.update_title(win, title, opts)
end

-- Create a buffer
function M.create_buffer(opts)
    return M.window.create_buffer(opts)
end

-- Apply syntax highlighting to a buffer
function M.apply_syntax(buf, syntax)
    vim.api.nvim_buf_set_option(buf, "filetype", syntax)
end

-- Set buffer text
function M.set_buffer_text(buf, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Get buffer text
function M.get_buffer_text(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

-- Set buffer keymap
function M.set_buffer_keymap(buf, mode, key, callback, opts)
    vim.api.nvim_buf_set_keymap(buf, mode, key, "", {
        noremap = true,
        silent = true,
        callback = callback,
        desc = opts and opts.desc,
    })
end

-- Set up autocmd for buffer
function M.buffer_autocmd(event, buf, callback)
    local group = vim.api.nvim_create_augroup("DoitBuffer" .. buf, { clear = true })
    vim.api.nvim_create_autocmd(event, {
        group = group,
        buffer = buf,
        callback = callback
    })
    return group
end

-- Center text in string of given width
function M.center_text(text, width)
    local padding = math.max(0, width - #text)
    local left_pad = math.floor(padding / 2)
    return string.rep(" ", left_pad) .. text
end

-- Format text with vertical border
function M.with_border(text, width, border_char)
    border_char = border_char or "│"
    return border_char .. " " .. text .. string.rep(" ", width - #text - 4) .. " " .. border_char
end

-- Create a bordered box with text
function M.create_box(lines, opts)
    opts = opts or {}
    local width = opts.width or 50
    local border_style = opts.border_style or "rounded"
    local title = opts.title
    local result = {}
    
    -- Border characters based on style
    local border = {
        rounded = { "╭", "╮", "╰", "╯", "─", "│" },
        single = { "┌", "┐", "└", "┘", "─", "│" },
        double = { "╔", "╗", "╚", "╝", "═", "║" },
        none = { "", "", "", "", "", "" },
    }
    
    local b = border[border_style] or border.rounded
    
    -- Top border
    local top_border = b[1] .. string.rep(b[5], width - 2) .. b[2]
    if title then
        local title_str = " " .. title .. " "
        local title_pos = math.floor((width - #title_str) / 2)
        top_border = b[1] .. string.rep(b[5], title_pos)
            .. title_str
            .. string.rep(b[5], width - 2 - title_pos - #title_str) .. b[2]
    end
    table.insert(result, top_border)
    
    -- Content
    for _, line in ipairs(lines) do
        table.insert(result, b[6] .. " " .. line .. string.rep(" ", width - #line - 4) .. " " .. b[6])
    end
    
    -- Bottom border
    table.insert(result, b[3] .. string.rep(b[5], width - 2) .. b[4])
    
    return result
end

return M