-- File system utilities for doit.nvim
local M = {}
local path = require("doit.core.utils.path")

-- Read file content
function M.read_file(file_path)
    local f = io.open(file_path, "r")
    if not f then
        return nil
    end
    
    local content = f:read("*all")
    f:close()
    
    return content
end

-- Write content to file
function M.write_file(file_path, content)
    -- Ensure directory exists
    local dir = path.dirname(file_path)
    if not path.ensure_dir(dir) then
        return false, "Failed to create directory: " .. dir
    end
    
    local f = io.open(file_path, "w")
    if not f then
        return false, "Failed to open file for writing: " .. file_path
    end
    
    f:write(content)
    f:close()
    
    return true
end

-- Read JSON file
function M.read_json(file_path)
    local content = M.read_file(file_path)
    if not content then
        return nil
    end
    
    local status, data = pcall(vim.fn.json_decode, content)
    if not status then
        return nil
    end
    
    return data
end

-- Write JSON file
function M.write_json(file_path, data)
    local status, json = pcall(vim.fn.json_encode, data)
    if not status then
        return false, "Failed to encode JSON"
    end
    
    return M.write_file(file_path, json)
end

-- List files in directory
function M.list_files(dir_path, pattern)
    pattern = pattern or ".*"
    local files = {}
    
    if not path.is_dir(dir_path) then
        return files
    end
    
    -- Use vim.fn.glob to get files
    local glob_pattern = dir_path .. "/*"
    local glob_files = vim.fn.glob(glob_pattern, false, true)
    
    for _, file in ipairs(glob_files) do
        if not path.is_dir(file) and file:match(pattern) then
            table.insert(files, file)
        end
    end
    
    return files
end

-- List directories
function M.list_dirs(dir_path)
    local dirs = {}
    
    if not path.is_dir(dir_path) then
        return dirs
    end
    
    -- Use vim.fn.glob to get directories
    local glob_pattern = dir_path .. "/*"
    local glob_files = vim.fn.glob(glob_pattern, false, true)
    
    for _, file in ipairs(glob_files) do
        if path.is_dir(file) then
            table.insert(dirs, file)
        end
    end
    
    return dirs
end

-- Rename file
function M.rename(old_path, new_path)
    local status, err = os.rename(old_path, new_path)
    if not status then
        return false, err
    end
    return true
end

-- Delete file
function M.delete(file_path)
    local status, err = os.remove(file_path)
    if not status then
        return false, err
    end
    return true
end

return M