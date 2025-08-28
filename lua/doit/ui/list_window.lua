local vim = vim

local config = require("doit.config")
-- Get the todo module and use its state
local core = require("doit.core")
local todo_module = core.get_module("todos")
local state = todo_module and todo_module.state or {}
local highlights = require("doit.ui.highlights")
local main_window = require("doit.ui.main_window")

local M = {}

local win_id = nil
local buf_id = nil
local timer = nil
local REFRESH_INTERVAL = 5000  -- Refresh every 5 seconds

-- Get active todos
local function get_active_todos()
    local active_todos = {}
    for _, todo in ipairs(state.todos) do
        if todo.in_progress and not todo.done then
            table.insert(active_todos, todo)
        end
    end
    return active_todos
end

function M.render_list()
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end
    
    vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
    
    -- Clear existing highlights
    local ns_id = highlights.get_namespace_id()
    vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
    
    -- Build lines array
    local lines = { " Active Todos:", "" }
    
    local active_todos = get_active_todos()
    if #active_todos == 0 then
        table.insert(lines, "  No active todos")
    else
        for _, todo in ipairs(active_todos) do
            table.insert(lines, "  " .. main_window.format_todo_line(todo))
        end
    end
    
    -- Set buffer content
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    
    -- Apply highlighting
    vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Title", 0, 0, -1)
    
    -- Set default formatting if not available
    if not config.options.formatting then
        config.options.formatting = {
            pending = { icon = "○" },
            in_progress = { icon = "◐" },
            done = { icon = "✓" }
        }
    end
    
    -- Highlight each todo line
    for i = 2, #lines do
        local line_nr = i
        local in_progress_icon = config.options.formatting.in_progress and config.options.formatting.in_progress.icon or "◐"
        if lines[i]:match("^%s+[" .. in_progress_icon .. "]") then
            local todo_index = i - 2  -- Adjust for header lines
            local todo = active_todos[todo_index]
            
            if todo then
                local hl_group = highlights.get_priority_highlight(todo.priorities, config)
                vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, line_nr, 0, -1)
                
                -- Tag highlight
                for tag in lines[i]:gmatch("#(%w+)") do
                    local start_idx = lines[i]:find("#" .. tag) - 1
                    vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Type", line_nr, start_idx, start_idx + #tag + 1)
                end
                
                -- Due date highlight
                if lines[i]:match("%[OVERDUE%]") then
                    local start_idx = lines[i]:find("%[OVERDUE%]")
                    vim.api.nvim_buf_add_highlight(buf_id, ns_id, "ErrorMsg", line_nr, start_idx - 1, start_idx + 8)
                end
            end
        end
    end
    
    vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

local function create_list_window()
    local ui = vim.api.nvim_list_uis()[1]
    local width = config.options.list_window and config.options.list_window.width or 40
    local height = config.options.list_window and config.options.list_window.height or 10
    local position = config.options.list_window and config.options.list_window.position or "bottom-right"
    local padding = 2
    
    -- Position calculation
    local col, row
    if position == "right" then
        col = ui.width - width - padding
        row = math.floor((ui.height - height) / 2)
    elseif position == "left" then
        col = padding
        row = math.floor((ui.height - height) / 2)
    elseif position == "top" then
        col = math.floor((ui.width - width) / 2)
        row = padding
    elseif position == "bottom" then
        col = math.floor((ui.width - width) / 2)
        row = ui.height - height - padding
    elseif position == "top-right" then
        col = ui.width - width - padding
        row = padding
    elseif position == "top-left" then
        col = padding
        row = padding
    elseif position == "bottom-right" then
        col = ui.width - width - padding
        row = ui.height - height - padding
    elseif position == "bottom-left" then
        col = padding
        row = ui.height - height - padding
    else
        col = math.floor((ui.width - width) / 2)
        row = math.floor((ui.height - height) / 2)
    end
    
    highlights.setup_highlights() -- initialize highlight groups
    
    buf_id = vim.api.nvim_create_buf(false, true)
    win_id = vim.api.nvim_open_win(buf_id, false, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " active to-dos ",
        title_pos = "center",
        footer = " [q] to close ",
        footer_pos = "center",
    })
    
    vim.api.nvim_win_set_option(win_id, "wrap", true)
    vim.api.nvim_win_set_option(win_id, "linebreak", true)
    vim.api.nvim_win_set_option(win_id, "breakindent", true)
    
    -- Setup close keymapping
    vim.keymap.set("n", "q", M.close_list_window, { buffer = buf_id, nowait = true })
    
    -- Setup auto-refresh
    if timer then
        timer:stop()
    end
    
    timer = vim.loop.new_timer()
    timer:start(0, REFRESH_INTERVAL, vim.schedule_wrap(function()
        if win_id and vim.api.nvim_win_is_valid(win_id) then
            M.render_list()
        else
            timer:stop()
        end
    end))
    
    -- Setup auto-close when focus lost
    vim.api.nvim_create_autocmd("WinLeave", {
        buffer = buf_id,
        callback = function()
            -- Don't close if moving to the main todo window
            local cur_win = vim.api.nvim_get_current_win()
            if cur_win ~= main_window.get_window_id() then
                M.close_list_window()
            end
            return true
        end,
    })
end

function M.toggle_list_window()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        M.close_list_window()
    else
        create_list_window()
        M.render_list()
    end
end

function M.close_list_window()
    if timer then
        timer:stop()
        timer = nil
    end
    
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, true)
        win_id = nil
        buf_id = nil
    end
end

return M