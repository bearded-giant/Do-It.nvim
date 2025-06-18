-- API for cross-module communication in doit.nvim
local M = {}

-- Setup API with framework reference
function M.setup(framework)
    M.framework = framework
    
    -- Module registry for plugin discovery
    M.modules = {}
    
    -- Register a module definition with the API
    function M.register(name, module_def)
        M.modules[name] = module_def
        return M.modules[name]
    end
    
    -- Get a module by name
    function M.get_module(name)
        return M.framework.modules[name]
    end
    
    -- Get module configuration
    function M.get_module_config(name)
        if framework.config and framework.config.modules and framework.config.modules[name] then
            return framework.config.modules[name]
        end
        return {}
    end
    
    -- Event system shorthand
    M.events = framework.events
    
    -- Projects API
    M.projects = {
        get_root = function()
            return framework.utils.project.get_root()
        end,
        
        get_identifier = function()
            return framework.utils.project.get_identifier()
        end,
        
        get_name = function()
            return framework.utils.project.get_name()
        end
    }
    
    return M
end

return M