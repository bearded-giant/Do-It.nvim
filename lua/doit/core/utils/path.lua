-- Path utilities for doit.nvim
local M = {}

-- Join path components
function M.join(...)
    local path_sep = package.config:sub(1,1) -- Path separator for the current OS
    local result = table.concat({...}, path_sep)
    return result
end

-- Get the directory part of a path
function M.dirname(path)
    local last_slash = path:match(".*/" .. "([^/]+)$")
    if last_slash then
        return path:sub(1, -(#last_slash + 2))
    end
    return path
end

-- Get the filename part of a path
function M.basename(path)
    return path:match("([^/]+)$")
end

-- Check if path exists
function M.exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- Check if path is a directory
function M.is_dir(path)
    return vim.fn.isdirectory(path) == 1
end

-- Create directory if it doesn't exist
function M.ensure_dir(path)
    if not M.is_dir(path) then
        local mkdir_cmd = vim.fn.has("win32") == 1 and "mkdir" or "mkdir -p"
        vim.fn.system(mkdir_cmd .. " " .. vim.fn.shellescape(path))
        return M.is_dir(path)
    end
    return true
end

-- Get home directory
function M.get_home()
    return vim.fn.expand("~")
end

-- Expand path (resolve ~ and environment variables)
function M.expand(path)
    return vim.fn.expand(path)
end

-- Normalize path (resolve .., etc.)
function M.normalize(path)
    return vim.fn.fnamemodify(path, ":p")
end

-- Get relative path
function M.relative(path, base)
    return vim.fn.fnamemodify(path, ":~:" .. base)
end

-- Get absolute path
function M.absolute(path)
    return vim.fn.fnamemodify(path, ":p")
end

-- Get data directory
function M.get_data_dir()
    return vim.fn.stdpath("data")
end

return M