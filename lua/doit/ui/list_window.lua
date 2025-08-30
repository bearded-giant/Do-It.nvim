local vim = vim

local config = require("doit.config")
local highlights = require("doit.ui.highlights")
local main_window = require("doit.ui.main_window")

local M = {}

local win_id = nil
local buf_id = nil
local timer = nil
local REFRESH_INTERVAL = 5000  -- Refresh every 5 seconds

-- Lazy loading of todo module and state
local todo_module = nil
local state = nil

local function get_todo_module()
    if not todo_module then
        local core = require("doit.core")
        todo_module = core.get_module("todos")
        
        -- If not loaded, try to load it
        if not todo_module then
            local doit = require("doit")
            if doit.load_module then
                todo_module = doit.load_module("todos", {})
            end
        end
    end
    return todo_module
end

-- Function to ensure state is loaded - always get fresh reference
local function ensure_state_loaded()
    local module = get_todo_module()
    if module and module.state then
        -- Always update reference to get current list state
        state = module.state
        return state
    else
        -- Fallback only if module not available
        if not state then
            -- Use compatibility shim as fallback
            local ok, compat_state = pcall(require, "doit.state")
            if ok then
                state = compat_state
            else
                -- Initialize empty state as last resort
                state = {
                    todos = {},
                    active_filter = nil,
                    deleted_todos = {},
                    sort_todos = function() end,
                    apply_filter = function(self) return self.todos end,
                }
            end
        end
        return state
    end
end

-- Get active todos
local function get_active_todos()
    local active_todos = {}
    local loaded_state = ensure_state_loaded()
    if loaded_state and loaded_state.todos then
        for _, todo in ipairs(loaded_state.todos) do
            if todo.in_progress and not todo.done then
                table.insert(active_todos, todo)
            end
        end
    end
    return active_todos
end

function M.render_list()
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
        return
    end
    
    -- Update window title with current list name
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        local loaded_state = ensure_state_loaded()
        local list_name = "default"
        if loaded_state and loaded_state.todo_lists and loaded_state.todo_lists.active then
            list_name = loaded_state.todo_lists.active
        end
        vim.api.nvim_win_set_config(win_id, {
            title = string.format(" active to-dos [%s] ", list_name),
            title_pos = "center",
        })
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
    -- Get the active list name for the window title
    local loaded_state = ensure_state_loaded()
    local list_name = "default"
    if loaded_state and loaded_state.todo_lists and loaded_state.todo_lists.active then
        list_name = loaded_state.todo_lists.active
    end
    
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
    win_id = vim.api.nvim_open_win(buf_id, true, {  -- Changed to true to give focus
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = string.format(" active to-dos [%s] ", list_name),
        title_pos = "center",
        footer = " [q] or [Esc] to close ",
        footer_pos = "center",
    })
    
    vim.api.nvim_win_set_option(win_id, "wrap", true)
    vim.api.nvim_win_set_option(win_id, "linebreak", true)
    vim.api.nvim_win_set_option(win_id, "breakindent", true)
    
    -- Setup close keymapping with proper closure
    vim.keymap.set("n", "q", function() M.close_list_window() end, { buffer = buf_id, nowait = true, desc = "Close list window" })
    vim.keymap.set("n", "<Esc>", function() M.close_list_window() end, { buffer = buf_id, nowait = true, desc = "Close list window" })
    
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
    
    -- Remove auto-close on focus lost - it interferes with keybindings
    -- Users should explicitly close with q or Esc
end

function M.toggle_list_window()
    -- Ensure state is loaded before toggle
    ensure_state_loaded()
    
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