-- Lua port of normalizeTodoText in mcp/todo-text.js. The two MUST agree: a todo
-- typed in nvim and the same todo created through MCP (which wraps it in a
-- claude:/[type]/rank/deps shell) have to compare equal for dedupe to work.
-- Shared fixtures live in tests/modules/todos/normalize_spec.lua and
-- mcp/todo-text.test.mjs.
local M = {}

function M.normalize(text)
    local s = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    s = s:gsub("^claude:%s*", "")

    -- [^%[%]]+ rejects both brackets, so a "[[note link]]" prefix survives
    -- instead of being eaten as a type tag.
    s = s:gsub("^%[[^%[%]]+%]%s*", "")

    -- the required trailing space keeps "1.5x throughput" and "3.buy milk" intact
    s = s:gsub("^%d+%a*%.%s+", "")

    s = s:gsub("%s*%(dep on [^)]*%)%s*$", "")

    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

return M
