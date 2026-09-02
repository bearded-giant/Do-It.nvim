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

-- Current tmux session name, or nil outside tmux
local function tmux_session_name()
    if not vim.env.TMUX or vim.fn.executable("tmux") == 0 then
        return nil
    end
    local cmd = "tmux display-message -p '#S'"
    if vim.env.TMUX_PANE then
        -- pane-targeted: correct even after the window moved between sessions
        cmd = "tmux display-message -p -t " .. vim.fn.shellescape(vim.env.TMUX_PANE) .. " '#S'"
    end
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 or not out then
        return nil
    end
    out = out:gsub("%s+$", "")
    if out == "" then
        return nil
    end
    return out
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

-- Save current list selection. The file is shared with the tmux and MCP
-- surfaces and carries a per-tmux-session 'sessions' link map, so this must
-- read-merge-write — a wholesale rewrite would clobber the other sessions'
-- links. Inside tmux the switch writes BOTH the session link and the global
-- pointer; outside tmux the global pointer only.
function M.save_session(list_name)
    if not list_name then
        return
    end

    local data = read_session()
    data.active_list = list_name
    data.timestamp = os.time()

    local sess = tmux_session_name()
    if sess then
        if type(data.sessions) ~= "table" then
            data.sessions = {}
        end
        data.sessions[sess] = list_name
    end
    -- an empty lua table json_encodes as [] which breaks the jq readers
    if type(data.sessions) == "table" and next(data.sessions) == nil then
        data.sessions = nil
    end

    local file = io.open(get_session_file(), "w")
    if file then
        local json = vim.fn.json_encode(data)
        file:write(json)
        file:close()
    end
end

-- Load last selected list. Returns (list_name, from_link): inside tmux the
-- session's linked list wins over the global pointer, and from_link tells the
-- caller the choice was an explicit link (which outranks project derivation).
function M.load_session()
    local data = read_session()

    local sess = tmux_session_name()
    if sess and type(data.sessions) == "table" and data.sessions[sess] then
        return data.sessions[sess], true
    end

    return data.active_list, false
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
