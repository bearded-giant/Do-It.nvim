-- Plugin management for doit.nvim
local M = {}

-- Discover available modules
function M.discover_modules()
    local modules = {}
    local config = require("doit.core.config").options
    
    -- Check if auto discovery is enabled
    if not config.plugins.auto_discover then
        return modules
    end
    
    -- Base module path
    local base_path = config.plugins.load_path:gsub("%.", "/")
    
    -- Find modules in runtimepath
    local paths = vim.api.nvim_get_runtime_file(base_path .. "/*", true)
    for _, path in ipairs(paths) do
        local module_name = vim.fn.fnamemodify(path, ":t")
        if vim.fn.isdirectory(path) == 1 then
            table.insert(modules, module_name)
        end
    end
    
    return modules
end

-- Load a module dynamically
function M.load_module(name)
    local config = require("doit.core.config").options
    local ok, module = pcall(require, config.plugins.load_path .. "." .. name)
    if ok and module then
        return module
    end
    return nil
end

-- Get standalone module path
function M.get_standalone_path(name)
    return "doit_" .. name
end

-- Load standalone module
function M.load_standalone(name)
    local module_path = M.get_standalone_path(name)
    local ok, module = pcall(require, module_path)
    if ok and module then
        return module
    end
    return nil
end

return M