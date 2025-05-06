-- Storage for notes module
local M = {}

-- Setup storage
function M.setup(state, parent_module)
    local config
    if parent_module and parent_module.config then
        config = parent_module.config
    else
        config = require("doit.modules.notes.config").options
    end
    
    -- Get project identifier from core
    function M.get_project_identifier()
        local core = require("doit.core")
        if core.utils and core.utils.project then
            return core.utils.project.get_identifier()
        end
        
        -- Fallback to project module if core utils not available
        local project_module = package.loaded["doit.state"] and package.loaded["doit.state"].get_project_identifier
        if project_module then
            return project_module()
        end
        
        return nil
    end
    
    -- Get storage path based on mode
    function M.get_storage_path(is_global)
        local base_path = config.storage_path or vim.fn.stdpath("data") .. "/doit/notes"
        
        -- Create the directory if it doesn't exist
        local mkdir_cmd = vim.fn.has("win32") == 1 and "mkdir" or "mkdir -p"
        vim.fn.system(mkdir_cmd .. " " .. vim.fn.shellescape(base_path))
        
        if not is_global and config.mode == "project" then
            local project_id = M.get_project_identifier()
            if project_id then
                local hash = vim.fn.sha256(project_id)
                return base_path .. "/project-" .. string.sub(hash, 1, 10) .. ".json"
            end
        end
        
        return base_path .. "/global.json"
    end
    
    -- Load notes from storage
    function M.load_notes()
        local is_global = state.notes.current_mode == "global"
        local file_path = M.get_storage_path(is_global)
        local result = { 
            id = state.generate_note_id(),
            content = "",
            title = is_global and "Global Notes" or "Project Notes",
            created_at = os.time(),
            updated_at = os.time(),
            metadata = {}
        }
        
        local success, f = pcall(io.open, file_path, "r")
        if success and f then
            local content = f:read("*all")
            f:close()
            if content and content ~= "" then
                local status, notes_data = pcall(vim.fn.json_decode, content)
                if status and notes_data and notes_data.content then
                    -- Ensure we have proper note metadata
                    notes_data.id = notes_data.id or state.generate_note_id()
                    notes_data.title = notes_data.title or (is_global and "Global Notes" or "Project Notes")
                    notes_data.created_at = notes_data.created_at or os.time()
                    notes_data.updated_at = notes_data.updated_at or os.time()
                    notes_data.metadata = notes_data.metadata or {}
                    
                    result = notes_data
                end
            end
        end
        
        if is_global then
            state.notes.global = result
        else
            local project_id = M.get_project_identifier()
            if project_id then
                state.notes.project[project_id] = result
            end
        end
        
        return result
    end
    
    -- Save notes to storage
    function M.save_notes(notes_content)
        if not notes_content then
            vim.notify("Invalid notes data provided", vim.log.levels.ERROR)
            return false
        end
        
        -- Ensure we have the required fields
        notes_content.id = notes_content.id or state.generate_note_id()
        notes_content.title = notes_content.title or (state.notes.current_mode == "global" and "Global Notes" or "Project Notes")
        notes_content.created_at = notes_content.created_at or os.time()
        notes_content.updated_at = os.time() -- Always update the timestamp
        notes_content.metadata = notes_content.metadata or {}
        
        local is_global = state.notes.current_mode == "global"
        local file_path = M.get_storage_path(is_global)
        
        local success, f = pcall(io.open, file_path, "w")
        if success and f then
            local status, json_content = pcall(vim.fn.json_encode, notes_content)
            if status then
                f:write(json_content)
                f:close()
                
                -- Check if this is a new note or an update
                local is_new = false
                local existing = nil
                
                if is_global then
                    existing = state.notes.global
                    state.notes.global = notes_content
                else
                    local project_id = M.get_project_identifier()
                    if project_id then
                        existing = state.notes.project[project_id]
                        state.notes.project[project_id] = notes_content
                    end
                end
                
                is_new = not existing or not existing.id
                
                -- Emit appropriate event
                local parent_module = parent_module
                
                if is_new and parent_module and parent_module.on_note_created then
                    parent_module.on_note_created(notes_content)
                elseif parent_module and parent_module.on_note_updated then
                    parent_module.on_note_updated(notes_content)
                end
                
                return true
            else
                vim.notify("Error encoding notes data", vim.log.levels.ERROR)
                f:close()
                return false
            end
        else
            vim.notify("Failed to save notes to file", vim.log.levels.ERROR)
            return false
        end
    end
    
    -- Switch between global and project notes
    function M.switch_mode()
        -- Toggle mode
        if state.notes.current_mode == "global" then
            state.notes.current_mode = "project"
        else
            state.notes.current_mode = "global"
        end
        
        -- Load notes for the new mode
        return M.load_notes()
    end
    
    -- Get current notes
    function M.get_current_notes()
        if state.notes.current_mode == "global" then
            return state.notes.global
        else
            local project_id = M.get_project_identifier()
            if project_id and state.notes.project[project_id] then
                return state.notes.project[project_id]
            end
            -- Load from disk if not in memory
            return M.load_notes()
        end
    end
    
    return M
end

return M