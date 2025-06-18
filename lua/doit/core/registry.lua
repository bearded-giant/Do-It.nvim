local M = {}

M.modules = {}

function M.is_registered(name)
    return M.modules[name] ~= nil
end

function M.register(name, info)
    if not name or type(name) ~= "string" then
        error("Module name must be a string")
    end
    
    local module_info = {
        name = name,
        path = info.path,
        version = info.version or "0.0.1",
        description = info.description or "",
        author = info.author or "",
        dependencies = info.dependencies or {},
        config_schema = info.config_schema or {},
        api = info.api or {},
        initialization_time = os.time()
    }
    
    M.modules[name] = module_info
    return module_info
end

function M.unregister(name)
    if M.modules[name] then
        local module = M.modules[name]
        M.modules[name] = nil
        return module
    end
    return nil
end

function M.get(name)
    return M.modules[name]
end

function M.list()
    local module_list = {}
    for name, info in pairs(M.modules) do
        table.insert(module_list, info)
    end
    
    table.sort(module_list, function(a, b)
        return a.name < b.name
    end)
    
    return module_list
end

function M.check_dependencies(name)
    local module = M.modules[name]
    if not module then
        return false, "Module not found"
    end
    
    local missing = {}
    
    for _, dep in ipairs(module.dependencies or {}) do
        if not M.modules[dep] then
            table.insert(missing, dep)
        end
    end
    
    if #missing > 0 then
        return false, "Missing dependencies: " .. table.concat(missing, ", ")
    end
    
    return true, "All dependencies satisfied"
end

function M.get_api(name)
    local module = M.modules[name]
    if not module then
        return nil
    end
    
    return module.api
end

function M.register_api(name, api_functions)
    local module = M.modules[name]
    if not module then
        return false
    end
    
    module.api = module.api or {}
    
    for func_name, func in pairs(api_functions) do
        if type(func) == "function" then
            module.api[func_name] = func
        end
    end
    
    return true
end

function M.call(module_name, func_name, ...)
    local module = M.modules[module_name]
    if not module or not module.api then
        return nil, "Module or API not found"
    end
    
    local func = module.api[func_name]
    if not func or type(func) ~= "function" then
        return nil, "Function not found in module API"
    end
    
    local success, result = pcall(func, ...)
    if success then
        return result
    else
        return nil, "Error calling function: " .. tostring(result)
    end
end

function M.extend_config_schema(name, schema)
    local module = M.modules[name]
    if not module then
        return false
    end
    
    module.config_schema = vim.tbl_deep_extend("force", module.config_schema or {}, schema or {})
    return true
end

function M.validate_config(name, config)
    local module = M.modules[name]
    if not module or not module.config_schema then
        return true, {}
    end
    
    -- TODO: Expand with proper JSON Schema validator
    local errors = {}
    
    for field, schema in pairs(module.config_schema) do
        if schema.required and config[field] == nil then
            table.insert(errors, string.format("Required field '%s' is missing", field))
        elseif config[field] ~= nil and schema.type and type(config[field]) ~= schema.type then
            table.insert(errors, string.format("Field '%s' should be of type '%s', got '%s'", 
                field, schema.type, type(config[field])))
        end
    end
    
    return #errors == 0, errors
end

function M.discover()
    local plugins = require("doit.core.plugins")
    local config = require("doit.core.config").options
    
    local discovered = plugins.discover_modules()
    local count = 0
    
    for _, name in ipairs(discovered) do
        if not M.is_registered(name) then
            local module_path = config.plugins.load_path .. "." .. name
            local success, module = pcall(require, module_path)
            
            if success and module then
                local metadata = module.metadata or {}
                metadata.path = module_path
                
                M.register(name, metadata)
                count = count + 1
            end
        end
    end
    
    return count
end

function M.register_custom_module(name, path, opts)
    if M.is_registered(name) then
        return false, "Module name already registered"
    end
    
    local success, module = pcall(require, path)
    if not success or not module then
        return false, "Failed to load module: " .. tostring(module)
    end
    
    local metadata = vim.tbl_extend("force", module.metadata or {}, opts or {})
    metadata.path = path
    metadata.custom = true
    
    M.register(name, metadata)
    
    return true, "Module registered successfully"
end

function M.initialize_module(name, config)
    local module_info = M.modules[name]
    if not module_info then
        return nil, "Module not registered"
    end
    
    local valid, errors = M.validate_config(name, config or {})
    if not valid then
        return nil, "Invalid configuration: " .. table.concat(errors, ", ")
    end
    
    local deps_ok, deps_msg = M.check_dependencies(name)
    if not deps_ok then
        return nil, deps_msg
    end
    
    local success, module = pcall(require, module_info.path)
    if not success or not module then
        return nil, "Failed to load module: " .. tostring(module)
    end
    
    if type(module.setup) == "function" then
        local success, result = pcall(module.setup, config or {})
        if success then
            return result
        else
            return nil, "Error initializing module: " .. tostring(result)
        end
    else
        return module, "Module loaded but has no setup function"
    end
end

return M