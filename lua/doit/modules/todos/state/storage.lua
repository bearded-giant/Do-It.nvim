-- Handles loading/saving from disk, plus importing/exporting.
local vim = vim

local storage = {
    -- Pre-define the functions to prevent nil value errors
    load_from_disk = function() end,
    save_to_disk = function() end,
    import_todos = function() return true, "Not implemented" end,
    export_todos = function() return true, "Not implemented" end
}

function storage.setup(M)
    -- Get module configuration
    local config
    local success, core_module = pcall(require, "doit.core")
    if success and core_module and core_module.get_module_config then
        config = core_module.get_module_config("todos")
    else
        -- Fallback configuration if core is not available
        config = {
            save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
            priorities = {}
        }
    end

    -- Redefine the functions with proper implementation
    storage.load_from_disk = function()
        if not config.save_path then
            config.save_path = vim.fn.stdpath("data") .. "/doit_todos.json"
        end

        local file = io.open(config.save_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            if content and content ~= "" then
                M.todos = vim.fn.json_decode(content)

                local needs_migration = false
                
                -- Migration: Add order_index if missing
                for i, todo in ipairs(M.todos) do
                    if not todo.order_index then
                        todo.order_index = i
                        needs_migration = true
                    end
                end
                
                -- Migration: Convert priorities from array to string
                for _, todo in ipairs(M.todos) do
                    if todo.priorities and type(todo.priorities) == "table" then
                        local highest_priority = nil
                        local highest_weight = 0
                        
                        for _, prio_name in ipairs(todo.priorities) do
                            for _, p in ipairs(config.priorities or {}) do
                                if p.name == prio_name and (p.weight or 0) > highest_weight then
                                    highest_weight = p.weight or 0
                                    highest_priority = prio_name
                                end
                            end
                        end
                        
                        todo.priorities = highest_priority
                        needs_migration = true
                    end
                end

                if needs_migration then
                    storage.save_to_disk()
                end
            end
        end
    end

    storage.save_to_disk = function()
        if not config.save_path then
            config.save_path = vim.fn.stdpath("data") .. "/doit_todos.json"
        end

        local file = io.open(config.save_path, "w")
        if file then
            file:write(vim.fn.json_encode(M.todos))
            file:close()
        end
    end

    storage.import_todos = function(file_path)
        local file = io.open(file_path, "r")
        if not file then
            return false, "Could not open file: " .. file_path
        end
        local content = file:read("*all")
        file:close()

        local status, imported_todos = pcall(vim.fn.json_decode, content)
        if not status then
            return false, "Error parsing JSON file"
        end

        -- Merge
        for _, todo in ipairs(imported_todos) do
            table.insert(M.todos, todo)
        end

        if M.sort_todos then
            M.sort_todos() -- from sorting.lua
        end
        storage.save_to_disk()
        return true, string.format("Imported %d todos", #imported_todos)
    end

    storage.export_todos = function(file_path)
        local file = io.open(file_path, "w")
        if not file then
            return false, "Could not open file for writing: " .. file_path
        end

        local json_content = vim.fn.json_encode(M.todos)
        file:write(json_content)
        file:close()
        return true, string.format("Exported %d todos to %s", #M.todos, file_path)
    end
    
    return storage
end

return storage