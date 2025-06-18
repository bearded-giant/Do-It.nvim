local M = {}

M.version = "2.0.0"

M.modules = {}

-- Cross-module event system for plugin communication
M.events = {
    listeners = {},
    
    on = function(event, callback)
        M.events.listeners[event] = M.events.listeners[event] or {}
        table.insert(M.events.listeners[event], callback)
        
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
    
    emit = function(event, data)
        if M.events.listeners[event] then
            local success_count = 0
            local error_count = 0
            
            for _, callback in ipairs(M.events.listeners[event]) do
                local success, err = pcall(callback, data)
                if success then
                    success_count = success_count + 1
                else
                    error_count = error_count + 1
                    vim.notify(
                        "Error in event handler for '" .. event .. "': " .. tostring(err),
                        vim.log.levels.ERROR
                    )
                end
            end
            
            return {
                event = event,
                listeners = #(M.events.listeners[event] or {}),
                success = success_count,
                errors = error_count
            }
        end
        
        return { event = event, listeners = 0, success = 0, errors = 0 }
    end,
    
    list = function()
        local events = {}
        for event, listeners in pairs(M.events.listeners) do
            table.insert(events, {
                name = event,
                listeners = #listeners
            })
        end
        return events
    end,
    
    clear = function(event)
        if event then
            M.events.listeners[event] = {}
        else
            M.events.listeners = {}
        end
    end
}

function M.register_module(name, module)
    M.modules[name] = module
    
    if module.commands then
        for cmd_name, cmd_def in pairs(module.commands) do
            vim.api.nvim_create_user_command(cmd_name, cmd_def.callback, cmd_def.opts or {})
        end
    end
    
    if module.keymaps then
        for key, mapping in pairs(module.keymaps) do
            vim.keymap.set(mapping.mode or "n", key, mapping.callback, mapping.opts or {})
        end
    end
    
    return module
end

function M.get_module(name)
    return M.modules[name]
end

function M.get_module_config(name)
    if M.config and M.config.modules and M.config.modules[name] then
        return M.config.modules[name]
    end
    return {}
end

function M.setup(opts)
    M.config = require("doit.core.config").setup(opts)
    
    M.utils = require("doit.core.utils")
    
    M.ui = require("doit.core.ui").setup()
    
    M.registry = require("doit.core.registry")
    
    M.api = require("doit.core.api").setup(M)
    
    vim.api.nvim_create_user_command("DoItDashboard", function()
        require("doit").show_dashboard()
    end, {
        desc = "Show DoIt dashboard with installed modules"
    })
    
    vim.api.nvim_create_user_command("DoItPlugins", function(opts)
        M.handle_plugin_command(opts)
    end, {
        desc = "Manage DoIt.nvim plugins",
        nargs = "*",
        complete = function(arglead, cmdline, cursorpos)
            local args = vim.split(cmdline, "%s+", { trimempty = true })
            if #args <= 2 then
                return { "list", "info", "install", "remove", "enable", "disable", "discover" }
            end
            
            if args[2] == "info" or args[2] == "remove" or args[2] == "enable" or args[2] == "disable" then
                local modules = M.registry.list()
                local module_names = {}
                for _, module in ipairs(modules) do
                    table.insert(module_names, module.name)
                end
                return module_names
            end
            
            return {}
        end
    })
    
    return M
end

function M.handle_plugin_command(opts)
    local args = opts.fargs or {}
    local cmd = args[1]
    
    if cmd == "list" then
        local modules = M.registry.list()
        
        if #modules == 0 then
            vim.notify("No modules registered", vim.log.levels.INFO)
            return
        end
        
        vim.notify("Registered modules:", vim.log.levels.INFO)
        for _, module in ipairs(modules) do
            local desc = module.description ~= "" and (" - " .. module.description) or ""
            local version = module.version ~= "" and (" (v" .. module.version .. ")") or ""
            local custom = module.custom and " [custom]" or ""
            
            vim.notify(module.name .. version .. custom .. desc, vim.log.levels.INFO)
        end
    elseif cmd == "info" then
        local module_name = args[2]
        if not module_name then
            vim.notify("Usage: DoItPlugins info <module_name>", vim.log.levels.ERROR)
            return
        end
        
        local module = M.registry.get(module_name)
        if not module then
            vim.notify("Module not found: " .. module_name, vim.log.levels.ERROR)
            return
        end
        
        local info = {
            "Module: " .. module.name,
            "Version: " .. (module.version or "unknown"),
            "Path: " .. (module.path or "unknown"),
            "Description: " .. (module.description or "No description"),
            "Author: " .. (module.author or "Unknown"),
            "Custom module: " .. (module.custom and "Yes" or "No"),
        }
        
        if module.dependencies and #module.dependencies > 0 then
            table.insert(info, "Dependencies: " .. table.concat(module.dependencies, ", "))
        end
        
        vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
    elseif cmd == "discover" then
        local count = M.registry.discover()
        vim.notify("Discovered " .. count .. " new modules", vim.log.levels.INFO)
    elseif cmd == "install" then
        local module_name = args[2]
        local module_path = args[3]
        
        if not module_name or not module_path then
            vim.notify("Usage: DoItPlugins install <module_name> <module_path>", vim.log.levels.ERROR)
            return
        end
        
        local success, msg = M.registry.register_custom_module(module_name, module_path)
        vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.ERROR)
    elseif cmd == "remove" then
        local module_name = args[2]
        if not module_name then
            vim.notify("Usage: DoItPlugins remove <module_name>", vim.log.levels.ERROR)
            return
        end
        
        local module = M.registry.unregister(module_name)
        if module then
            vim.notify("Module removed: " .. module_name, vim.log.levels.INFO)
        else
            vim.notify("Module not found: " .. module_name, vim.log.levels.ERROR)
        end
    else
        vim.notify([[
Usage: DoItPlugins <command> [args...]

Commands:
  list               List all registered modules
  info <name>        Show detailed information about a module
  discover           Discover new modules
  install <n> <path> Install a custom module
  remove <name>      Remove a module from the registry
        ]], vim.log.levels.INFO)
    end
end

return M