-- Core framework module for doit.nvim
local M = {}

-- Framework version
M.version = "2.0.0"

-- Registered modules
M.modules = {}

-- Event system for cross-module communication
M.events = {
    listeners = {},
    
    -- Subscribe to an event
    on = function(event, callback)
        M.events.listeners[event] = M.events.listeners[event] or {}
        table.insert(M.events.listeners[event], callback)
        
        -- Return a function to unsubscribe
        return function()
            local listeners = M.events.listeners[event]
            for i, listener in ipairs(listeners) do
                if listener == callback then
                    table.remove(listeners, i)
                    break
                end
            end
        end
    end,
    
    -- Emit an event
    emit = function(event, data)
        if M.events.listeners[event] then
            for _, callback in ipairs(M.events.listeners[event]) do
                callback(data)
            end
        end
    end
}

-- Register a module with the framework
function M.register_module(name, module)
    M.modules[name] = module
    
    -- Register module's commands if provided
    if module.commands then
        for cmd_name, cmd_def in pairs(module.commands) do
            vim.api.nvim_create_user_command(cmd_name, cmd_def.callback, cmd_def.opts or {})
        end
    end
    
    -- Register module's keymaps if provided
    if module.keymaps then
        for key, mapping in pairs(module.keymaps) do
            vim.keymap.set(mapping.mode or "n", key, mapping.callback, mapping.opts or {})
        end
    end
    
    return module
end

-- Get a registered module
function M.get_module(name)
    return M.modules[name]
end

-- Get module configuration
function M.get_module_config(name)
    if M.config and M.config.modules and M.config.modules[name] then
        return M.config.modules[name]
    end
    return {}
end

-- Initialize the core framework
function M.setup(opts)
    -- Setup core configuration
    M.config = require("doit.core.config").setup(opts)
    
    -- Initialize utilities
    M.utils = require("doit.core.utils")
    
    -- Initialize UI utilities
    M.ui = require("doit.core.ui")
    
    -- Initialize API
    M.api = require("doit.core.api").setup(M)
    
    return M
end

return M