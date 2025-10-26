local M = {}

-- Lazy loading of todo module and state
local todo_module = nil
local state = nil
local initialized = false

local function get_todo_module()
    if not todo_module then
        -- Try to get the module from core first
        local ok, core = pcall(require, "doit.core")
        if ok and core.get_module then
            todo_module = core.get_module("todos")
        end
        
        -- If not loaded through core, try to load it directly
        if not todo_module then
            local ok2, doit = pcall(require, "doit")
            if ok2 and doit.load_module then
                todo_module = doit.load_module("todos", {})
            end
        end
        
        -- Last resort: try to load the module directly
        if not todo_module then
            local ok3, todos = pcall(require, "doit.modules.todos")
            if ok3 then
                todo_module = todos
                -- Initialize if needed
                if todo_module.setup and not todo_module.state then
                    todo_module.setup({})
                end
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
        
        -- Initialize state if needed
        if not initialized then
            if state.load_from_disk and type(state.load_from_disk) == "function" then
                pcall(state.load_from_disk)
            end
            initialized = true
        end
        
        return state
    end
    
    -- Fallback to compatibility shim
    if not state then
        local ok, compat_state = pcall(require, "doit.state")
        if ok then
            state = compat_state
            if not initialized and state and state.load_from_disk then
                pcall(state.load_from_disk)
                initialized = true
            end
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
    local loaded_state = ensure_state_loaded()
    
    if not loaded_state or not loaded_state.todos or #loaded_state.todos == 0 then
        return ""
    end
    
    -- Find active todo
    local active = nil
    for _, todo in ipairs(loaded_state.todos) do
        if todo.in_progress and not todo.done then
            active = todo
            break
        end
    end
    
    if not active then
        return ""
    end
    
    -- Get config
    local ok, config = pcall(require, "doit.config")
    local icon = "◐"
    local max_length = 30
    
    if ok and config.options then
        if config.options.formatting and config.options.formatting.in_progress then
            icon = config.options.formatting.in_progress.icon or "◐"
        end
        if config.options.lualine and config.options.lualine.max_length then
            max_length = config.options.lualine.max_length
        end
    end
    
    -- Format the text - truncate if needed
    local text = active.text:gsub("\n", " ")
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

    -- Get todo count for current list (exclude completed todos)
    local todo_count = 0
    if loaded_state.todos then
        for _, todo in ipairs(loaded_state.todos) do
            if not todo.done then
                todo_count = todo_count + 1
            end
        end
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