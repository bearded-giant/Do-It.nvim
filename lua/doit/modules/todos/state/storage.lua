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
            default_list = "default",
            priorities = {}
        }
    end

    -- Get the configured default list name
    local default_list_name = config.default_list or "default"
    
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
        config.active_list = default_list_name
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
                        local todo_count = 0
                        pcall(function()
                            local data = vim.fn.json_decode(content)
                            if data._metadata then
                                metadata = data._metadata
                            end
                            -- Count active todos in the list (exclude completed)
                            if data.todos then
                                for _, todo in ipairs(data.todos) do
                                    if not todo.done then
                                        todo_count = todo_count + 1
                                    end
                                end
                            end
                        end)

                        -- Add active todo count to metadata
                        metadata.todo_count = todo_count
                        
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
            list_name = default_list_name
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
            list_name = default_list_name
        end
        
        local list_path = get_list_path(list_name)
        
        -- Debug logging
        if config.development_mode then
            vim.notify(string.format("Loading list '%s' from path: %s", list_name, list_path), vim.log.levels.DEBUG)
        end
        
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
                    
                    -- Save session for persistence
                    local session = require("doit.modules.todos.state.session")
                    session.save_session(list_name)
                    
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
            storage.load_list(default_list_name)
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
            
            -- Update session with new name
            local session = require("doit.modules.todos.state.session")
            session.save_session(new_name)
        end
        
        return true, "Renamed list '" .. old_name .. "' to '" .. new_name .. "'"
    end
    
    -- Load from disk (compatibility with older versions)
    storage.load_from_disk = function()
        -- Handle migration from old save path if needed
        if config.save_path and vim.fn.filereadable(config.save_path) == 1 and
           vim.fn.filereadable(get_list_path(default_list_name)) == 0 then
            -- Old file exists but new default list doesn't - migrate
            local file = io.open(config.save_path, "r")
            if file then
                local content = file:read("*all")
                file:close()

                if content and content ~= "" then
                    local success, todos = pcall(vim.fn.json_decode, content)
                    if success and todos then
                        storage.create_list(default_list_name, todos, {
                            migrated_from = config.save_path,
                            migrated_at = os.time()
                        })
                    end
                end
            end
        end
        
        -- Try to restore last session's list
        local session = require("doit.modules.todos.state.session")
        local last_list = session.load_session()
        
        if last_list then
            -- Verify the list still exists
            local list_path = get_list_path(last_list)
            if vim.fn.filereadable(list_path) == 1 then
                config.active_list = last_list
            end
        end
        
        -- Load the configured active list
        storage.load_list(config.active_list)
        
        -- Get available lists
        storage.get_available_lists()
    end
    
    -- Save to disk with multi-list support
    storage.save_to_disk = function()
        local list_name = M.todo_lists.active or default_list_name
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
            list_name = M.todo_lists.active or default_list_name
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

    storage.move_todo_to_list = function(todo_id, destination_list_name)
        if not destination_list_name or destination_list_name == "" then
            return false, "Invalid destination list name"
        end

        -- Ensure we have the latest state
        if not M.todos or #M.todos == 0 then
            return false, "No todos in current list"
        end

        -- Find the todo in the current list
        local todo_to_move = nil
        local todo_index = nil

        for i, todo in ipairs(M.todos) do
            -- Handle both old format (no ID) and new format (with ID)
            local current_id = todo.id or (todo.created_at and (todo.created_at .. "_" .. i))
            if current_id == todo_id then
                todo_to_move = vim.deepcopy(todo)
                todo_index = i
                break
            end
        end

        if not todo_to_move then
            -- Debug: List all todo IDs to help diagnose
            local available_ids = {}
            for i, todo in ipairs(M.todos) do
                table.insert(available_ids, todo.id or "no-id")
            end
            return false, string.format("Todo with ID '%s' not found. Available: %s",
                tostring(todo_id), table.concat(available_ids, ", "))
        end

        -- Verify destination list exists
        local dest_list_path = get_list_path(destination_list_name)
        if vim.fn.filereadable(dest_list_path) == 0 then
            return false, "Destination list does not exist"
        end

        -- IMPORTANT: Create backup of current state before ANY modifications
        local backup_todos = vim.deepcopy(M.todos)
        local backup_metadata = vim.deepcopy(M.todo_lists.metadata)

        local source_list_name = M.todo_lists.active or default_list_name
        local source_list_path = get_list_path(source_list_name)

        -- Load destination list
        local file = io.open(dest_list_path, "r")
        if not file then
            return false, "Could not open destination list"
        end

        local content = file:read("*all")
        file:close()

        local dest_data = {}
        local success, decoded = pcall(vim.fn.json_decode, content)
        if not success or not decoded then
            return false, "Failed to parse destination list"
        end

        dest_data = decoded
        local dest_todos = dest_data.todos or {}

        -- Prepare destination data (without modifying M.todos yet)
        local updated_todo = vim.deepcopy(todo_to_move)
        updated_todo.order_index = #dest_todos + 1
        table.insert(dest_todos, updated_todo)

        dest_data.todos = dest_todos
        dest_data._metadata = dest_data._metadata or {}
        dest_data._metadata.updated_at = os.time()

        -- Prepare source data (create modified copy without touching M.todos)
        local source_todos = vim.deepcopy(M.todos)
        table.remove(source_todos, todo_index)

        -- Update order_index for remaining todos in the copy
        for i = todo_index, #source_todos do
            source_todos[i].order_index = i
        end

        local source_data = {
            _metadata = vim.deepcopy(M.todo_lists.metadata) or {},
            todos = source_todos
        }
        source_data._metadata.updated_at = os.time()

        -- Now try to save both files WITHOUT modifying M.todos yet
        -- Save destination first
        local dest_file = io.open(dest_list_path, "w")
        if not dest_file then
            -- Nothing modified yet, safe to return
            return false, "Failed to open destination list for writing"
        end

        local dest_json = vim.fn.json_encode(dest_data)
        local write_success = pcall(function()
            dest_file:write(dest_json)
            dest_file:close()
        end)

        if not write_success then
            pcall(function() dest_file:close() end)
            -- Nothing modified yet, safe to return
            return false, "Failed to write to destination list"
        end

        -- Save source list
        local source_file = io.open(source_list_path, "w")
        if not source_file then
            -- Destination was saved, but we failed to save source
            -- This is a problem, but at least in-memory state is still intact
            return false, "Failed to open source list for writing (destination was updated)"
        end

        local source_json = vim.fn.json_encode(source_data)
        write_success = pcall(function()
            source_file:write(source_json)
            source_file:close()
        end)

        if not write_success then
            pcall(function() source_file:close() end)
            -- Both files might be in inconsistent state, but in-memory is still intact
            -- Restore in-memory state to be safe
            return false, "Failed to write to source list (destination was updated)"
        end

        -- SUCCESS: Both files saved successfully
        -- Now and ONLY now update the in-memory state
        M.todos = source_todos
        if M.todo_lists.metadata then
            M.todo_lists.metadata.updated_at = os.time()
        end

        return true, string.format("Moved todo to list '%s'", destination_list_name)
    end

    return storage
end

return storage