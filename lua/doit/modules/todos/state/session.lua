-- Session management for persistent list selection
local M = {}

-- Get session file path - global across all projects
local function get_session_file()
    -- Use stdpath for consistent cross-platform storage
    local session_dir = vim.fn.stdpath("data") .. "/doit"
    vim.fn.mkdir(session_dir, "p")

    -- Global session file shared across all projects
    return session_dir .. "/session.json"
end

-- field separator for tmux format output; window names can hold tabs and spaces
local SEP = "\31"

-- Run tmux with an argv list; stdout without its trailing newline, nil on failure
local function tmux(args)
    local out = vim.fn.system(vim.list_extend({ "tmux" }, args))
    if vim.v.shell_error ~= 0 or not out then
        return nil
    end
    return (out:gsub("\n$", ""))
end

-- This nvim's tmux window, or nil outside tmux: id, live (its @doit-window-list
-- link, which follows the window through renames and moves), and key
-- ("<session>:<window name>", what the link persists under in session.json)
local function tmux_window()
    if not vim.env.TMUX or vim.fn.executable("tmux") == 0 then
        return nil
    end
    local args = { "display-message", "-p" }
    if vim.env.TMUX_PANE then
        -- pane-targeted: correct even after the window moved between sessions
        vim.list_extend(args, { "-t", vim.env.TMUX_PANE })
    end
    table.insert(args, "#{window_id}" .. SEP .. "#{@doit-window-list}" .. SEP .. "#S:#W")
    local id, live, key = (tmux(args) or ""):match("^([^\31]*)\31([^\31]*)\31(.+)$")
    if not id then
        return nil
    end
    return { id = id, live = live ~= "" and live or nil, key = key }
end

-- the key stamp lets tmux/scripts/todo-relink.sh move the persisted copy on a rename
local function set_window_link(win, list_name)
    tmux({ "set-option", "-wq", "-t", win.id, "@doit-window-list", list_name })
    tmux({ "set-option", "-wq", "-t", win.id, "@doit-window-key", win.key })
end

-- id/value pairs of every live window's tmux option `name`
local function live_windows(name)
    local out = tmux({ "list-windows", "-a", "-F", "#{window_id}" .. SEP .. "#{" .. name .. "}" }) or ""
    local rows = {}
    for line in out:gmatch("[^\n]+") do
        local id, value = line:match("^([^\31]*)\31(.*)$")
        if id then
            table.insert(rows, { id = id, value = value })
        end
    end
    return rows
end

-- true when a live window other than win already holds the link persisted for win.key
local function key_claimed_elsewhere(win)
    for _, row in ipairs(live_windows("@doit-window-key")) do
        if row.id ~= win.id and row.value == win.key then
            return true
        end
    end
    return false
end

local function read_session()
    local file = io.open(get_session_file(), "r")
    if not file then
        return {}
    end
    local content = file:read("*all")
    file:close()

    if content and content ~= "" then
        local success, data = pcall(vim.fn.json_decode, content)
        if success and type(data) == "table" then
            return data
        end
    end
    return {}
end

local function write_session(data)
    -- an empty lua table json_encodes as [] which breaks the jq readers
    if type(data.sessions) == "table" and next(data.sessions) == nil then
        data.sessions = nil
    end
    -- tmp + rename: tmux and the MCP must never read a half-written file and fall back to {}
    local path = get_session_file()
    local tmp = path .. "." .. vim.fn.getpid() .. ".tmp"
    local file = io.open(tmp, "w")
    if file then
        file:write(vim.fn.json_encode(data))
        file:close()
        os.rename(tmp, path)
    end
end

function M.read()
    return read_session()
end

function M.update(mutate)
    local data = read_session()
    mutate(data)
    write_session(data)
end

-- Save current list selection. The file is shared with the tmux and MCP
-- surfaces and carries a per-tmux-window 'sessions' link map, so this must
-- read-merge-write — a wholesale rewrite would clobber the other windows'
-- links. Inside tmux the switch writes BOTH the window link (live option and
-- persisted copy) and the global pointer; outside tmux the global pointer only.
function M.save_session(list_name)
    if not list_name then
        return
    end

    local data = read_session()
    data.active_list = list_name
    data.timestamp = os.time()

    local win = tmux_window()
    if win then
        if type(data.sessions) ~= "table" then
            data.sessions = {}
        end
        data.sessions[win.key] = list_name
        set_window_link(win, list_name)
    end

    write_session(data)
end

-- Every window linked to old_name, live and persisted, now links new_name.
function M.relink_list(old_name, new_name)
    local data = read_session()
    if type(data.sessions) == "table" then
        local changed = false
        for key, list in pairs(data.sessions) do
            if list == old_name then
                data.sessions[key] = new_name
                changed = true
            end
        end
        if changed then
            write_session(data)
        end
    end
    if vim.env.TMUX and vim.fn.executable("tmux") == 1 then
        for _, row in ipairs(live_windows("@doit-window-list")) do
            if row.value == old_name then
                tmux({ "set-option", "-wq", "-t", row.id, "@doit-window-list", new_name })
            end
        end
    end
end

local function window_link(win, data)
    if win.live then
        return win.live
    end
    -- a tmux restart drops window options: the link persisted under this
    -- window's name comes back, unless a same-named live window holds it
    local link = type(data.sessions) == "table" and data.sessions[win.key] or nil
    if link and not key_claimed_elsewhere(win) then
        set_window_link(win, link)
        return link
    end
    return nil
end

-- Load last selected list. Returns (list_name, from_link). Inside tmux only
-- the window link counts: an unlinked window gets nil (the caller's default
-- list), never the global pointer, which is the outside-tmux default. from_link
-- tells the caller the choice was an explicit link (outranks project derivation).
function M.load_session()
    local data = read_session()

    local win = tmux_window()
    if win then
        local link = window_link(win, data)
        return link, link ~= nil
    end

    return data.active_list, false
end

function M.window_key()
    local win = tmux_window()
    return win and win.key
end

-- Persisted links grouped by list: { [list] = { { key = "<session>:<window>", live = bool }, ... } },
-- plus the list this window links. nil outside tmux.
function M.links_by_list()
    local win = tmux_window()
    if not win then
        return nil
    end
    local data = read_session()

    local live = {}
    for key in (tmux({ "list-windows", "-a", "-F", "#S:#W" }) or ""):gmatch("[^\n]+") do
        live[key] = true
    end

    local by_list = {}
    for key, list in pairs(type(data.sessions) == "table" and data.sessions or {}) do
        by_list[list] = by_list[list] or {}
        table.insert(by_list[list], { key = key, live = live[key] == true })
    end
    for _, links in pairs(by_list) do
        table.sort(links, function(a, b)
            return a.key < b.key
        end)
    end

    return by_list, window_link(win, data)
end

-- Global pointer only; window links stay as they are.
function M.set_global(list_name)
    if not list_name then
        return
    end
    M.update(function(data)
        data.active_list = list_name
    end)
end

-- Unlink this window, live and persisted. Returns its key, nil outside tmux.
function M.unlink_window()
    local win = tmux_window()
    if not win then
        return nil
    end
    tmux({ "set-option", "-wqu", "-t", win.id, "@doit-window-list" })
    tmux({ "set-option", "-wqu", "-t", win.id, "@doit-window-key" })
    -- a same-named window may hold the persisted link; leave it to that window
    if not key_claimed_elsewhere(win) then
        M.update(function(data)
            if type(data.sessions) == "table" then
                data.sessions[win.key] = nil
            end
        end)
    end
    return win.key
end

-- Clean old sessions (optional)
function M.clean_old_sessions(days)
    days = days or 30
    local session_dir = vim.fn.stdpath("data") .. "/doit/sessions"
    
    if vim.fn.isdirectory(session_dir) == 0 then
        return
    end
    
    local now = os.time()
    local cutoff = now - (days * 24 * 60 * 60)
    
    local files = vim.fn.glob(session_dir .. "/*.json", false, true)
    for _, file_path in ipairs(files) do
        local file = io.open(file_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            local success, data = pcall(vim.fn.json_decode, content)
            if success and data and data.timestamp then
                if data.timestamp < cutoff then
                    os.remove(file_path)
                end
            end
        end
    end
end

return M
