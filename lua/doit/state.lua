-- Compatibility shim for legacy state module
-- This module provides backwards compatibility by forwarding to the modular todos state

local core = require("doit.core")
local todo_module = core.get_module("todos")

if not todo_module then
    -- If todos module isn't loaded, try to load it
    local doit = require("doit")
    if doit.load_module then
        todo_module = doit.load_module("todos", {})
    end
end

-- Return the todo module's state or an empty table if not available
return todo_module and todo_module.state or {}