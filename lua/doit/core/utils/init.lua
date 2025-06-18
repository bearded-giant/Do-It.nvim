-- Core utilities for doit.nvim
local M = {}

-- Initialize all utility modules
function M.setup()
    M.path = require("doit.core.utils.path")
    M.fs = require("doit.core.utils.fs")
    M.project = require("doit.core.utils.project")
    return M
end

-- Common utility functions
M.is_table = function(t)
    return type(t) == "table"
end

M.is_string = function(s)
    return type(s) == "string"
end

M.is_function = function(f)
    return type(f) == "function"
end

M.is_nil = function(n)
    return n == nil
end

-- Generate a unique ID
M.generate_id = function()
    return tostring(math.random(100000, 999999))
end

-- Merge two tables
M.merge_tables = function(t1, t2)
    local result = {}
    for k, v in pairs(t1) do
        result[k] = v
    end
    for k, v in pairs(t2) do
        result[k] = v
    end
    return result
end

-- Get timestamp
M.get_timestamp = function()
    return os.time()
end

-- Format relative time
M.format_relative_time = function(timestamp)
    if not timestamp then
        return ""
    end
    
    local now = os.time()
    local diff = now - timestamp
    
    if diff < 60 then
        return "just now"
    elseif diff < 3600 then
        local mins = math.floor(diff / 60)
        return mins .. "m ago"
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. "h ago"
    elseif diff < 604800 then
        local days = math.floor(diff / 86400)
        return days .. "d ago"
    elseif diff < 2592000 then
        local weeks = math.floor(diff / 604800)
        return weeks .. "w ago"
    else
        local months = math.floor(diff / 2592000)
        return months .. "mo ago"
    end
end

return M