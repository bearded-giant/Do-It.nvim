-- Actions for managing todos
local M = {}

-- Setup function for the todos actions component
function M.setup(module)
    -- Initialize with module reference for state access
    local state = module.state
    local config = module.config
    
    -- Forward commonly used actions from the core implementation
    -- with proper state and module context
    
    function M.new_todo(on_render)
        -- Create wrapper for the core implementation
        local core_actions = require("doit.ui.todo_actions")
        core_actions.new_todo(on_render)
    end
    
    function M.toggle_todo(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.toggle_todo(win_id, on_render)
    end
    
    function M.delete_todo(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.delete_todo(win_id, on_render)
    end
    
    function M.delete_completed(on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.delete_completed(on_render)
    end
    
    function M.remove_duplicates(on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.remove_duplicates(on_render)
    end
    
    function M.edit_todo(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.edit_todo(win_id, on_render)
    end
    
    function M.edit_priorities(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.edit_priorities(win_id, on_render)
    end
    
    function M.add_time_estimation(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.add_time_estimation(win_id, on_render)
    end
    
    function M.remove_time_estimation(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.remove_time_estimation(win_id, on_render)
    end
    
    function M.add_due_date(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.add_due_date(win_id, on_render)
    end
    
    function M.remove_due_date(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.remove_due_date(win_id, on_render)
    end
    
    function M.reorder_todo(win_id, on_render)
        local core_actions = require("doit.ui.todo_actions")
        core_actions.reorder_todo(win_id, on_render)
    end
    
    -- Return module with all functions
    return M
end

return M