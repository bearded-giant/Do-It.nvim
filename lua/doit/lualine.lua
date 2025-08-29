local M = {}

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

-- Function to ensure state is loaded
local function ensure_state_loaded()
    local module = get_todo_module()
    if module and module.state then
        state = module.state
        return state
    else
        -- Fallback to compatibility shim
        local ok, compat_state = pcall(require, "doit.state")
        if ok then
            state = compat_state
            return state
        end
    end
    return nil
end

local function get_active_todo()
    local loaded_state = ensure_state_loaded()
    if not loaded_state or not loaded_state.todos then
        return nil
    end
    
    for _, todo in ipairs(loaded_state.todos) do
        if todo.in_progress and not todo.done then
            return todo
        end
    end
    return nil
end

function M.active_todo()
    local active = get_active_todo()
    if not active then
        return ""
    end
    
    -- Get config
    local config = require("doit.config")
    
    -- Get icon from config
    local icon = config.options.formatting.in_progress.icon or "◐"
    
    -- Format the text - truncate if needed
    local text = active.text:gsub("\n", " ")
    local max_length = config.options.lualine and config.options.lualine.max_length or 30
    
    if #text > max_length then
        text = text:sub(1, max_length) .. "..."
    end
    
    return icon .. " " .. text
end

function M.current_list()
    local loaded_state = ensure_state_loaded()
    if not loaded_state then
        return ""
    end
    
    local list_name = "default"
    if loaded_state.todo_lists and loaded_state.todo_lists.active then
        list_name = loaded_state.todo_lists.active
    end
    
    -- Get todo count for current list
    local todo_count = 0
    if loaded_state.todos then
        todo_count = #loaded_state.todos
    end
    
    -- Return formatted list info
    return string.format("📋 %s (%d)", list_name, todo_count)
end

function M.todo_stats()
    local loaded_state = ensure_state_loaded()
    if not loaded_state or not loaded_state.todos then
        return ""
    end
    
    local done = 0
    local in_progress = 0
    local pending = 0
    
    for _, todo in ipairs(loaded_state.todos) do
        if todo.done then
            done = done + 1
        elseif todo.in_progress then
            in_progress = in_progress + 1
        else
            pending = pending + 1
        end
    end
    
    -- Show in order: in-progress, pending, done
    -- Using clearer text labels instead of just icons
    return string.format("▶ %d | ○ %d | ✓ %d", in_progress, pending, done)
end

function M.setup()
    -- This is just a helper function to make setup easier
    -- User still needs to configure lualine separately
    return {
        active_todo = M.active_todo,
        current_list = M.current_list,
        todo_stats = M.todo_stats,
    }
end

return M