-- Project utilities for doit.nvim
local M = {}

-- Cache for project information
M.cache = {}

-- Get project root directory
function M.get_root()
    local config = require("doit.core.config").options
    
    if not config.project.enabled then
        return nil
    end
    
    local cwd = vim.fn.getcwd()
    
    -- Check cache first
    if M.cache[cwd] then
        return M.cache[cwd].root
    end
    
    local project_root = nil
    
    -- Try to get git root if enabled
    if config.project.detection.use_git then
        local cmd = 'git -C ' .. vim.fn.shellescape(cwd) .. ' rev-parse --show-toplevel 2>/dev/null'
        local git_root = vim.fn.system(cmd):gsub('\n', '')
        if git_root ~= "" then
            project_root = git_root
        end
    end
    
    -- Fallback to current working directory if enabled
    if not project_root and config.project.detection.fallback_to_cwd then
        project_root = cwd
    end
    
    -- Cache the result
    M.cache[cwd] = {
        root = project_root,
        identifier = project_root and M.hash_path(project_root) or nil,
        name = project_root and vim.fn.fnamemodify(project_root, ":t") or "Global"
    }
    
    return project_root
end

-- Hash a path to create a unique identifier
function M.hash_path(path)
    local hash = vim.fn.sha256(path)
    return string.sub(hash, 1, 10)
end

-- Get project identifier (hash of project path)
function M.get_identifier()
    local root = M.get_root()
    if not root then
        return nil
    end
    
    local cwd = vim.fn.getcwd()
    if M.cache[cwd] and M.cache[cwd].identifier then
        return M.cache[cwd].identifier
    end
    
    return M.hash_path(root)
end

-- Get project name (last directory name)
function M.get_name()
    local root = M.get_root()
    if not root then
        return "Global"
    end
    
    local cwd = vim.fn.getcwd()
    if M.cache[cwd] and M.cache[cwd].name then
        return M.cache[cwd].name
    end
    
    return vim.fn.fnamemodify(root, ":t")
end

-- Clear project cache
function M.clear_cache()
    M.cache = {}
end

-- Get project storage path
function M.get_storage_path(module_name, suffix)
    local config = require("doit.core.config").options
    local project_id = M.get_identifier()
    
    if not project_id then
        return nil
    end
    
    local storage_dir = config.project.storage.path
    local path_utils = require("doit.core.utils.path")
    path_utils.ensure_dir(storage_dir)
    
    local filename = "project-" .. project_id
    if module_name then
        filename = module_name .. "-" .. filename
    end
    
    if suffix then
        filename = filename .. suffix
    end
    
    return path_utils.join(storage_dir, filename .. ".json")
end

return M