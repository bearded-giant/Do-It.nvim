-- Todos module for doit.nvim
local M = {}

-- Module version
M.version = "2.0.0"

-- Setup function for the todos module
function M.setup(opts)
    -- Initialize module with core framework
    local core = require("doit.core")
    
    -- Setup module configuration
    local config = require("doit.modules.todos.config")
    M.config = config.setup(opts)
    
    -- Initialize state
    M.state = require("doit.modules.todos.state")
    M.state.load_todos()
    
    -- Initialize UI
    M.ui = require("doit.modules.todos.ui")
    
    -- Initialize commands
    M.commands = require("doit.modules.todos.commands").setup(M)
    
    -- Register module with core
    core.register_module("todos", M)
    
    -- Set up keymaps from config
    M.setup_keymaps()
    
    -- Listen for events from other modules if they exist
    if core.get_module("notes") then
        core.events.on("note_updated", function(data)
            -- Handle note updates if needed
        end)
    end
    
    return M
end

-- Set up module keymaps
function M.setup_keymaps()
    local config = M.config
    
    -- Main window toggle
    if config.keymaps.toggle_window then
        vim.keymap.set("n", config.keymaps.toggle_window, function()
            M.ui.main_window.toggle_todo_window()
        end, { desc = "Toggle Todo List" })
    end
    
    -- List window toggle
    if config.keymaps.toggle_list_window then
        vim.keymap.set("n", config.keymaps.toggle_list_window, function()
            M.ui.list_window.toggle_list_window()
        end, { desc = "Toggle Active Todo List" })
    end
end

-- Standalone entry point (when used without the framework)
function M.standalone_setup(opts)
    -- Create minimal core if it doesn't exist
    if not package.loaded["doit.core"] then
        -- Minimal core implementation
        local minimal_core = {
            register_module = function() return end,
            get_module = function() return nil end,
            events = {
                on = function() return function() end end,
                emit = function() return end
            }
        }
        package.loaded["doit.core"] = minimal_core
    end
    
    return M.setup(opts)
end

return M