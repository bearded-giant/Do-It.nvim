-- State management for the todos module
local M = {}

-- Default values to prevent nil errors
M.load_from_disk = function() end
M.save_to_disk = function() end
M.update_priority_weights = function() end

-- Setup function for state
function M.setup(parent_module)
    -- Core state data
    M.todos = {} -- main list of todos
    M.active_filter = nil -- optional active tag filter
    M.deleted_todos = {} -- history of deleted todos for undo
    M.MAX_UNDO_HISTORY = 100
    M.reordering_todo_index = nil -- currently reordering todo index
    
    -- Get parent module config
    local config
    if parent_module and parent_module.config then
        config = parent_module.config
    else
        config = require("doit.modules.todos.config").options
    end
    
    -- Load sub-modules
    local storage_module = require("doit.modules.todos.state.storage")
    local todos_ops = require("doit.modules.todos.state.todos")
    local priorities = require("doit.modules.todos.state.priorities")
    local due_dates = require("doit.modules.todos.state.due_dates")
    local search_ops = require("doit.modules.todos.state.search")
    local sorting_ops = require("doit.modules.todos.state.sorting")
    local tags_ops = require("doit.modules.todos.state.tags")
    local categories_ops = require("doit.modules.todos.state.categories")
    
    -- Initialize storage first to get the storage functions
    local storage = storage_module.setup(M)
    
    -- Directly assign storage functions to M
    M.load_from_disk = storage.load_from_disk
    M.save_to_disk = storage.save_to_disk
    M.import_todos = storage.import_todos
    M.export_todos = storage.export_todos
    
    -- Initialize other sub-modules
    todos_ops.setup(M)
    priorities.setup(M)
    due_dates.setup(M)
    search_ops.setup(M)
    sorting_ops.setup(M)
    tags_ops.setup(M)
    categories_ops.setup(M)
    
    -- Forward key functions directly to M
    for _, module in ipairs({todos_ops, priorities, due_dates, search_ops, sorting_ops, tags_ops, categories_ops}) do
        for name, func in pairs(module) do
            if type(func) == "function" and not M[name] then
                M[name] = func
            end
        end
    end
    
    -- Forward storage list management functions to M
    M.create_list = storage.create_list
    M.load_list = storage.load_list
    M.delete_list = storage.delete_list
    M.rename_list = storage.rename_list
    M.get_available_lists = storage.get_available_lists
    
    return M
end

-- Alias/convenience function for loading todos
function M.load_todos()
    -- Load from disk, then update priority weights
    M.load_from_disk() -- from storage.lua
    M.update_priority_weights() -- from priorities.lua
end

-- Alias for saving todos
function M.save_todos()
    M.save_to_disk()
end

return M