local M = {}

-- Machine-managed "last modified" footer on todo descriptions. Matches either
-- verb so older "last updated" stamps are stripped too (no stacking on re-save).
local FOOTER_PATTERN = "\n*%-%-%-%-%-%-%-%-%-%-\nlast %a+:.*$"

function M.strip(desc)
    return (desc or ""):gsub(FOOTER_PATTERN, "")
end

-- Append a fresh footer. Body may be empty (footer-only) — every todo carries a stamp.
function M.stamp(desc)
    local body = M.strip(desc):gsub("%s+$", "")
    return body .. "\n\n\n----------\nlast modified: " .. os.date("%Y-%m-%d: %H:%M")
end

return M
