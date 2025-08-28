-- Handles loading/saving from disk, plus importing/exporting.
local vim = vim

local storage = {
    -- Pre-define the functions to prevent nil value errors
    load_from_disk = function() end,
    save_to_disk = function() end,
    create_list = function() return true, "Not implemented" end,
    load_list = function() return true, "Not implemented" end,
    delete_list = function() return true, "Not implemented" end,
    rename_list = function() return true, "Not implemented" end,
    get_available_lists = function() return {} end,
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
            lists_dir = vim.fn.stdpath("data") .. "/doit/lists",
            active_list = "default",
            priorities = {}
        }
    end
    
    -- Ensure lists directory exists
    if not config.lists_dir then
        -- Check if lists configuration exists
        if config.lists and config.lists.save_path then
            config.lists_dir = config.lists.save_path
        elseif config.storage and config.storage.save_path then
            -- Use storage.save_path as base for lists
            local base_path = config.storage.save_path
            if base_path:match("%.json$") then
                -- Remove filename if it's a json file path
                base_path = vim.fn.fnamemodify(base_path, ":h")
            end
            config.lists_dir = base_path .. "/lists"
        else
            config.lists_dir = vim.fn.stdpath("data") .. "/doit/lists"
        end
    end
    
    -- Create directory if it doesn't exist
    local mkdir_cmd = vim.fn.has("win32") == 1 and "mkdir" or "mkdir -p"
    vim.fn.system(mkdir_cmd .. " " .. vim.fn.shellescape(config.lists_dir))
    
    -- Set default active list if not specified
    if not config.active_list then
        config.active_list = "default"
    end
    
    -- Track list names and paths
    M.todo_lists = {
        available = {},
        active = config.active_list
    }

    -- Get list of available todo lists
    storage.get_available_lists = function()
        local lists = {}
        
        -- Check if lists directory exists
        if vim.fn.isdirectory(config.lists_dir) == 0 then
            return lists
        end
        
        -- Get all JSON files in the lists directory
        local ls_command = string.format("ls %s/*.json 2>/dev/null || true", vim.fn.shellescape(config.lists_dir))
        local output = vim.fn.systemlist(ls_command)
        
        -- Parse list names
        for _, file_path in ipairs(output) do
            local name = file_path:match("[^/]+%.json$")
            if name then
                name = name:gsub("%.json$", "")
                
                -- Load list metadata
                local file = io.open(file_path, "r")
                if file then
                    local content = file:read("*all")
                    file:close()
                    
                    if content and content ~= "" then
                        local metadata = {}
                        pcall(function()
                            local data = vim.fn.json_decode(content)
                            if data._metadata then
                                metadata = data._metadata
                            end
                        end)
                        
                        table.insert(lists, {
                            name = name,
                            path = file_path,
                            metadata = metadata
                        })
                    end
                end
            end
        end
        
        M.todo_lists.available = lists
        return lists
    end
    
    -- Get the path for a specific list
    local function get_list_path(list_name)
        if not list_name or list_name == "" then
            list_name = "default"
        end
        
        return config.lists_dir .. "/" .. list_name .. ".json"
    end
    
    -- Create a new todo list
    storage.create_list = function(list_name, initial_todos, metadata)
        if not list_name or list_name == "" then
            return false, "Invalid list name"
        end
        
        -- Check if list already exists
        local list_path = get_list_path(list_name)
        if vim.fn.filereadable(list_path) == 1 then
            return false, "List '" .. list_name .. "' already exists"
        end
        
        -- Create the list file
        local todos = initial_todos or {}
        local data = {
            _metadata = metadata or {
                created_at = os.time(),
                updated_at = os.time()
            },
            todos = todos
        }
        
        local file = io.open(list_path, "w")
        if not file then
            return false, "Failed to create list file"
        end
        
        file:write(vim.fn.json_encode(data))
        file:close()
        
        -- Update available lists
        storage.get_available_lists()
        
        return true, "Created list '" .. list_name .. "'"
    end
    
    -- Load a specific todo list
    storage.load_list = function(list_name)
        if not list_name or list_name == "" then
            list_name = "default"
        end
        
        local list_path = get_list_path(list_name)
        
        -- Check if file exists, if not create a default list
        if vim.fn.filereadable(list_path) == 0 then
            storage.create_list(list_name, {})
        end
        
        local file = io.open(list_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            if content and content ~= "" then
                local data = {}
                local success, decoded = pcall(vim.fn.json_decode, content)
                
                if success and decoded then
                    data = decoded
                    
                    -- Extract todos and metadata
                    M.todos = data.todos or {}
                    M.todo_lists.metadata = data._metadata or {
                        created_at = os.time(),
                        updated_at = os.time()
                    }
                    
                    local needs_migration = false
                    
                    -- Migration: Add order_index if missing
                    for i, todo in ipairs(M.todos) do
                        if not todo.order_index then
                            todo.order_index = i
                            needs_migration = true
                        end
                        
                        -- Add unique ID if missing
                        if not todo.id then
                            todo.id = os.time() .. "_" .. math.random(1000000, 9999999)
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
                    
                    -- Update active list
                    M.todo_lists.active = list_name
                    config.active_list = list_name
                    
                    return true, "Loaded list '" .. list_name .. "'"
                end
            end
        end
        
        -- If loading failed, initialize with empty list
        M.todos = {}
        M.todo_lists.active = list_name
        config.active_list = list_name
        
        return false, "Failed to load list or list is empty"
    end
    
    -- Delete a todo list
    storage.delete_list = function(list_name)
        if not list_name or list_name == "" then
            return false, "Invalid list name"
        end
        
        local list_path = get_list_path(list_name)
        
        -- Check if file exists
        if vim.fn.filereadable(list_path) == 0 then
            return false, "List does not exist"
        end
        
        -- Delete file
        local success, err = os.remove(list_path)
        if not success then
            return false, "Failed to delete list: " .. (err or "unknown error")
        end
        
        -- Update available lists
        storage.get_available_lists()
        
        -- If we deleted the active list, switch to default
        if M.todo_lists.active == list_name then
            storage.load_list("default")
        end
        
        return true, "Deleted list '" .. list_name .. "'"
    end
    
    -- Rename a todo list
    storage.rename_list = function(old_name, new_name)
        if not old_name or old_name == "" or not new_name or new_name == "" then
            return false, "Invalid list name"
        end
        
        local old_path = get_list_path(old_name)
        local new_path = get_list_path(new_name)
        
        -- Check if source exists and destination doesn't
        if vim.fn.filereadable(old_path) == 0 then
            return false, "Source list does not exist"
        end
        
        if vim.fn.filereadable(new_path) == 1 then
            return false, "Destination list already exists"
        end
        
        -- Rename file
        local success = os.rename(old_path, new_path)
        if not success then
            return false, "Failed to rename list"
        end
        
        -- Update available lists
        storage.get_available_lists()
        
        -- If we renamed the active list, update active list name
        if M.todo_lists.active == old_name then
            M.todo_lists.active = new_name
            config.active_list = new_name
        end
        
        return true, "Renamed list '" .. old_name .. "' to '" .. new_name .. "'"
    end
    
    -- Load from disk (compatibility with older versions)
    storage.load_from_disk = function()
        -- Handle migration from old save path if needed
        if config.save_path and vim.fn.filereadable(config.save_path) == 1 and 
           vim.fn.filereadable(get_list_path("default")) == 0 then
            -- Old file exists but new default list doesn't - migrate
            local file = io.open(config.save_path, "r")
            if file then
                local content = file:read("*all")
                file:close()
                
                if content and content ~= "" then
                    local success, todos = pcall(vim.fn.json_decode, content)
                    if success and todos then
                        storage.create_list("default", todos, {
                            migrated_from = config.save_path,
                            migrated_at = os.time()
                        })
                    end
                end
            end
        end
        
        -- Load the configured active list
        storage.load_list(config.active_list)
        
        -- Get available lists
        storage.get_available_lists()
    end
    
    -- Save to disk with multi-list support
    storage.save_to_disk = function()
        local list_name = M.todo_lists.active or "default"
        local list_path = get_list_path(list_name)
        
        -- Update metadata
        local metadata = M.todo_lists.metadata or {}
        metadata.updated_at = os.time()
        
        -- Prepare data structure
        local data = {
            _metadata = metadata,
            todos = M.todos
        }
        
        -- Save to file
        local file = io.open(list_path, "w")
        if file then
            file:write(vim.fn.json_encode(data))
            file:close()
            return true
        end
        
        return false
    end

    storage.import_todos = function(file_path, list_name)
        -- If list_name not provided, import to active list
        if not list_name then
            list_name = M.todo_lists.active or "default"
        end
        
        local file = io.open(file_path, "r")
        if not file then
            return false, "Could not open file: " .. file_path
        end
        local content = file:read("*all")
        file:close()

        -- Try to parse the imported data
        local status, imported_data = pcall(vim.fn.json_decode, content)
        if not status then
            return false, "Error parsing JSON file"
        end
        
        -- Check if the imported file has the new format (with _metadata and todos)
        local imported_todos = nil
        local imported_metadata = nil
        
        if imported_data.todos and type(imported_data.todos) == "table" then
            -- New format with metadata
            imported_todos = imported_data.todos
            imported_metadata = imported_data._metadata
        elseif type(imported_data) == "table" and #imported_data > 0 then
            -- Old format, direct array of todos
            imported_todos = imported_data
        else
            return false, "Invalid format in imported file"
        end
        
        if not imported_todos then
            return false, "No todos found in imported file"
        end
        
        -- Handle importing to a new list
        if list_name ~= M.todo_lists.active then
            -- Create a new list with the imported todos
            local success, msg = storage.create_list(list_name, imported_todos, imported_metadata)
            if not success then
                return false, msg
            end
            
            -- Switch to the new list
            storage.load_list(list_name)
            return true, string.format("Created new list '%s' with %d imported todos", list_name, #imported_todos)
        end
        
        -- Otherwise, merge with current list
        for _, todo in ipairs(imported_todos) do
            -- Ensure each todo has an ID
            if not todo.id then
                todo.id = os.time() .. "_" .. math.random(1000000, 9999999)
            end
            
            -- Add order_index if missing
            if not todo.order_index then
                todo.order_index = #M.todos + 1
            end
            
            table.insert(M.todos, todo)
        end

        if M.sort_todos then
            M.sort_todos() -- from sorting.lua
        end
        
        storage.save_to_disk()
        return true, string.format("Imported %d todos to list '%s'", #imported_todos, list_name)
    end

    storage.export_todos = function(file_path, export_format)
        local file = io.open(file_path, "w")
        if not file then
            return false, "Could not open file for writing: " .. file_path
        end
        
        local json_content = ""
        
        if export_format == "simple" then
            -- Simple format - just an array of todos
            json_content = vim.fn.json_encode(M.todos)
        else
            -- Full format with metadata
            local data = {
                _metadata = M.todo_lists.metadata or {
                    name = M.todo_lists.active,
                    exported_at = os.time()
                },
                todos = M.todos
            }
            json_content = vim.fn.json_encode(data)
        end
        
        file:write(json_content)
        file:close()
        
        return true, string.format("Exported %d todos from list '%s' to %s", 
                                   #M.todos, M.todo_lists.active, file_path)
    end
    
    return storage
end

return storage