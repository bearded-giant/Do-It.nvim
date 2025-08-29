local vim = vim

local config = require("doit.config")
local highlights = require("doit.ui.highlights")

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

local M = {}

local win_id = nil
local buf_id = nil
local parent_win_id = nil

function M.close_category_window()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, true)
        win_id = nil
        buf_id = nil
    end
end

function M.create_category_window(caller_win_id)
    -- Close existing window if it's open
    M.close_category_window()

    parent_win_id = caller_win_id
    
    -- Ensure state is loaded
    local loaded_state = ensure_state_loaded()

    local categories = {}
    local category_counts = {}

    -- Extract categories from todos
    if loaded_state and loaded_state.todos then
        for _, todo in ipairs(loaded_state.todos) do
        local cat = todo.category or "Uncategorized"
        if not category_counts[cat] then
            category_counts[cat] = 0
            table.insert(categories, cat)
        end
            category_counts[cat] = category_counts[cat] + 1
        end
    end

    -- Sort categories alphabetically
    table.sort(categories)

    -- Create buffer
    buf_id = vim.api.nvim_create_buf(false, true)
    
    -- Calculate dimensions
    local lines = { " Filter by Category:", "" }
    for _, category in ipairs(categories) do
        table.insert(lines, string.format("  %s (%d)", category, category_counts[category]))
    end
    table.insert(lines, "")
    table.insert(lines, " [Enter] Select  [Esc] Close")

    local height = #lines
    local width = 40
    
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
    vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")

    local parent_pos = vim.api.nvim_win_get_position(parent_win_id)
    local parent_width = vim.api.nvim_win_get_width(parent_win_id)
    local parent_height = vim.api.nvim_win_get_height(parent_win_id)
    
    local row = parent_pos[1] + math.floor((parent_height - height) / 2)
    local col = parent_pos[2] + math.floor((parent_width - width) / 2)
    
    win_id = vim.api.nvim_open_win(buf_id, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Categories ",
        title_pos = "center",
    })

    -- Highlight the category list
    local ns_id = highlights.get_namespace_id()
    vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Title", 0, 0, -1)

    -- If there's an active category filter, highlight it
    if state.active_category then
        for i, line in ipairs(lines) do
            if line:match("^%s+" .. state.active_category .. " %(") then
                vim.api.nvim_buf_add_highlight(buf_id, ns_id, "IncSearch", i-1, 0, -1)
                -- Move cursor to the active category
                vim.api.nvim_win_set_cursor(win_id, {i, 0})
                break
            end
        end
    end

    -- Set up keymaps
    vim.keymap.set("n", "<CR>", function()
        local line_nr = vim.api.nvim_win_get_cursor(win_id)[1]
        local line = vim.api.nvim_buf_get_lines(buf_id, line_nr - 1, line_nr, false)[1]
        local category = line:match("^%s+(.-)%s+%(")
        
        if category then
            state.set_category_filter(category == "Uncategorized" and "" or category)
            M.close_category_window()
            
            -- Notify the parent window to re-render
            if parent_win_id and vim.api.nvim_win_is_valid(parent_win_id) then
                local main_window = require("doit.ui.main_window")
                main_window.render_todos()
            end
        end
    end, { buffer = buf_id, nowait = true })

    vim.keymap.set("n", "<Esc>", function()
        M.close_category_window()
    end, { buffer = buf_id, nowait = true })

    vim.keymap.set("n", "q", function()
        M.close_category_window()
    end, { buffer = buf_id, nowait = true })

    -- Auto-close the window if the parent window is closed
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(parent_win_id),
        callback = function()
            M.close_category_window()
        end,
        once = true,
    })
end

return M