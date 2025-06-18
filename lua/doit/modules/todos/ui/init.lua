-- UI components for the todos module
local M = {}

-- Setup function for the todos UI
function M.setup(module)
    -- Load all UI components and pass module reference
    M.highlights = require("doit.modules.todos.ui.highlights")
    M.todo_actions = require("doit.modules.todos.ui.todo_actions")
    
    -- Initialize components with module reference if they have setup function
    local components = {
        "help_window",
        "tag_window", 
        "search_window", 
        "scratchpad", 
        "main_window", 
        "list_window",
        "list_manager_window",
        "category_window"
    }
    
    for _, name in ipairs(components) do
        local comp = require("doit.modules.todos.ui." .. name)
        if comp.setup and type(comp.setup) == "function" then
            M[name] = comp.setup(module)
        else
            M[name] = comp
        end
    end
    
    return M
end

return M