local M = {}
local config = require("doit.config")

-- Initialize with defaults
M.notes = {
    global = { content = "" },
    project = {},
    current_mode = "project",
}

-- Get current project path from project module
local function get_project_identifier()
    return require("doit.state").get_project_identifier()
end

-- Get storage path based on mode
function M.get_storage_path(is_global)
    local base_path = config.options.notes.storage_path or vim.fn.stdpath("data") .. "/doit/notes"
    
    -- Create the directory if it doesn't exist
    local mkdir_cmd = vim.fn.has("win32") == 1 and "mkdir" or "mkdir -p"
    vim.fn.system(mkdir_cmd .. " " .. vim.fn.shellescape(base_path))
    
    if not is_global and config.options.notes.mode == "project" then
        local project_id = get_project_identifier()
        if project_id then
            local hash = vim.fn.sha256(project_id)
            return base_path .. "/project-" .. string.sub(hash, 1, 10) .. ".json"
        end
    end
    
    return base_path .. "/global.json"
end

-- Load notes from storage
function M.load_notes()
    local is_global = M.notes.current_mode == "global"
    local file_path = M.get_storage_path(is_global)
    local result = { content = "" }
    
    local success, f = pcall(io.open, file_path, "r")
    if success and f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local status, notes_data = pcall(vim.fn.json_decode, content)
            if status and notes_data and notes_data.content then
                result = notes_data
            end
        end
    end
    
    if is_global then
        M.notes.global = result
    else
        local project_id = get_project_identifier()
        if project_id then
            M.notes.project[project_id] = result
        end
    end
    
    return result
end

-- Save notes to storage
function M.save_notes(notes_content)
    if not notes_content then
        vim.notify("Invalid notes data provided", vim.log.levels.ERROR)
        return
    end
    
    local is_global = M.notes.current_mode == "global"
    local file_path = M.get_storage_path(is_global)
    
    local success, f = pcall(io.open, file_path, "w")
    if success and f then
        local status, json_content = pcall(vim.fn.json_encode, notes_content)
        if status then
            f:write(json_content)
            f:close()
            
            if is_global then
                M.notes.global = notes_content
            else
                local project_id = get_project_identifier()
                if project_id then
                    M.notes.project[project_id] = notes_content
                end
            end
        else
            vim.notify("Error encoding notes data", vim.log.levels.ERROR)
            f:close()
        end
    else
        vim.notify("Failed to save notes to file", vim.log.levels.ERROR)
    end
end

-- Switch between global and project notes
function M.switch_mode()
    -- Toggle mode
    if M.notes.current_mode == "global" then
        M.notes.current_mode = "project"
    else
        M.notes.current_mode = "global"
    end
    
    -- Load notes for the new mode
    return M.load_notes()
end

-- Get current notes
function M.get_current_notes()
    if M.notes.current_mode == "global" then
        return M.notes.global
    else
        local project_id = get_project_identifier()
        if project_id and M.notes.project[project_id] then
            return M.notes.project[project_id]
        end
        -- Load from disk if not in memory
        return M.load_notes()
    end
end

return M