local state = require("doit.state")
local main_window = require("doit.ui.main_window")
local config = require("doit.config")

local M = {}

local function get_active_todo()
    for _, todo in ipairs(state.todos) do
        if todo.in_progress and not todo.done then
            return todo
        end
    end
    return nil
end

function M.active_todo()
    local active = get_active_todo()
    if not active then
        return ""
    end
    
    -- Get icon from config
    local icon = config.options.formatting.in_progress.icon or "◐"
    
    -- Format the text - truncate if needed
    local text = active.text:gsub("\n", " ")
    local max_length = config.options.lualine and config.options.lualine.max_length or 30
    
    if #text > max_length then
        text = text:sub(1, max_length) .. "..."
    end
    
    return icon .. " " .. text
end

function M.setup()
    -- This is just a helper function to make setup easier
    -- User still needs to configure lualine separately
    return {
        active_todo = M.active_todo
    }
end

return M