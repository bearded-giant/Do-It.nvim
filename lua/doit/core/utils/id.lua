-- Unique ids for todos and notes.
--
-- The plugin never seeded math.random, so a bare `nvim --headless` produced the
-- SAME first draw every run — two instances minting an id in the same second
-- collided with certainty, and the docker test harness hit that case every time.
-- Ids are the anchor for nested todos (parent_id) and note links, so a collision
-- silently reparents or relinks the wrong item.
--
-- Format is unchanged ("<unix seconds>_<7 digits>") so existing ids, the MCP
-- generator and the tmux scripts all stay compatible.
local M = {}

local seeded = false
local counter = 0

local function ensure_seeded()
    if seeded then
        return
    end
    -- hrtime is monotonic nanoseconds; pid separates instances that start within
    -- the same nanosecond tick
    local uv = vim.uv or vim.loop
    local entropy = (uv and uv.hrtime and uv.hrtime() or os.clock() * 1e9) % 2147483647
    math.randomseed((entropy + vim.fn.getpid()) % 2147483647)
    seeded = true
end

-- `taken` is an optional set or list used to reject a collision outright rather
-- than trusting probability.
function M.generate(taken)
    ensure_seeded()

    local used = {}
    if type(taken) == "table" then
        if vim.islist and vim.islist(taken) or taken[1] ~= nil then
            for _, item in ipairs(taken) do
                local id = type(item) == "table" and item.id or item
                if id then
                    used[id] = true
                end
            end
        else
            used = taken
        end
    end

    for _ = 1, 100 do
        counter = counter + 1
        local id = string.format("%d_%d", os.time(), math.random(1000000, 9999999))
        if not used[id] then
            return id
        end
    end

    -- 100 collisions means something is very wrong; fall back to something that
    -- cannot repeat within this process
    counter = counter + 1
    return string.format("%d_%d_%d", os.time(), vim.fn.getpid(), counter)
end

return M
