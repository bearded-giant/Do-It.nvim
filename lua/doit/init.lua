local M = {}

-- Framework version
M.version = "2.0.0"

-- Setup function for the entire framework
function M.setup(opts)
    opts = opts or {}
    
    -- Ensure modules table exists
    if not opts.modules then
        opts.modules = {}
    end
    
    -- Initialize core
    M.core = require("doit.core").setup(opts)
    
    -- Discover modules if enabled
    if opts.plugins and opts.plugins.auto_discover then
        local plugins = require("doit.core.plugins")
        local discovered = plugins.discover_modules()
        
        for _, name in ipairs(discovered) do
            local module_opts = opts.modules[name] or {}
            if module_opts.enabled ~= false then
                M.load_module(name, module_opts)
            end
        end
    end
    
    -- Load explicitly configured modules
    for name, module_opts in pairs(opts.modules) do
        if module_opts.enabled ~= false and not M[name] then
            M.load_module(name, module_opts)
        end
    end
    
    -- Legacy behavior: Always load todos and notes modules if not disabled
    if not M.todos and (not opts.modules or (opts.modules.todos and opts.modules.todos.enabled ~= false)) then
        M.load_module("todos", (opts.modules and opts.modules.todos) or {})
    end
    
    if not M.notes and (not opts.modules or (opts.modules.notes and opts.modules.notes.enabled ~= false)) then
        M.load_module("notes", (opts.modules and opts.modules.notes) or {})
    end
    
    -- Forward old API calls for backwards compatibility
    M.state = M.todos and M.todos.state or {}
    M.ui = {}
    
    if M.todos then
        -- Forward state functions
        for name, func in pairs(M.todos.state) do
            if type(func) == "function" and not M.state[name] then
                M.state[name] = func
            end
        end
        
        -- Forward UI components
        for name, component in pairs(M.todos.ui) do
            M.ui[name] = component
        end
    end
    
    if M.notes then
        -- Forward notes UI
        M.ui.notes_window = M.notes.ui.notes_window
    end
    
    -- Add lualine component
    M.lualine = require("doit.lualine")
    
    return M
end

-- Load a specific module
function M.load_module(name, opts)
    local success, module = pcall(require, "doit.modules." .. name)
    
    if success and module then
        M[name] = module.setup(opts)
        return M[name]
    else
        vim.notify("Do-It.nvim: Failed to load module '" .. name .. "'", vim.log.levels.WARN)
        return nil
    end
end

return M