local M = {}

function M.setup(framework)
    M.framework = framework
    
    M.modules = {}
    
    function M.register(name, module_def)
        M.modules[name] = module_def
        return M.modules[name]
    end
    
    function M.get_module(name)
        return M.framework.modules[name]
    end
    
    function M.get_module_config(name)
        if framework.config and framework.config.modules and framework.config.modules[name] then
            return framework.config.modules[name]
        end
        return {}
    end
    
    M.events = framework.events
    
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