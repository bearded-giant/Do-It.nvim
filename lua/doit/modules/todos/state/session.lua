-- Session management for persistent list selection
local M = {}

-- Get session file path for current project
local function get_session_file()
    -- Use stdpath for consistent cross-platform storage
    local session_dir = vim.fn.stdpath("data") .. "/doit/sessions"
    vim.fn.mkdir(session_dir, "p")
    
    -- Get current working directory as project identifier
    local cwd = vim.fn.getcwd()
    -- Convert path to safe filename
    local safe_name = cwd:gsub("[/\\:]", "_"):gsub("^_+", "")
    
    return session_dir .. "/" .. safe_name .. ".json"
end

-- Save current list selection
function M.save_session(list_name)
    if not list_name then
        return
    end
    
    local session_file = get_session_file()
    local session_data = {
        active_list = list_name,
        cwd = vim.fn.getcwd(),
        timestamp = os.time()
    }
    
    local file = io.open(session_file, "w")
    if file then
        local json = vim.fn.json_encode(session_data)
        file:write(json)
        file:close()
    end
end

-- Load last selected list for current project
function M.load_session()
    local session_file = get_session_file()
    
    if vim.fn.filereadable(session_file) == 0 then
        return nil
    end
    
    local file = io.open(session_file, "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        if content and content ~= "" then
            local success, data = pcall(vim.fn.json_decode, content)
            if success and data then
                return data.active_list
            end
        end
    end
    
    return nil
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