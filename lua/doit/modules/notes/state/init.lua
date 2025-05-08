-- State management for notes module
local M = {}

-- Initialize notes state
function M.setup(parent_module)
    -- Load storage module
    local storage = require("doit.modules.notes.state.storage")
    
    -- Initialize with storage and parent module
    storage.setup(M, parent_module)
    
    -- Forward storage functions
    for name, func in pairs(storage) do
        if type(func) == "function" and not M[name] then
            M[name] = func
        end
    end
    
    -- Initialize notes state
    M.notes = {
        global = { content = "" },
        project = {},
        current_mode = "project",
    }
    
    -- Generate a summary from note content
    function M.generate_summary(content)
        if not content or content == "" then
            return ""
        end
        
        -- Get the first non-empty line
        local first_line = ""
        for line in content:gmatch("[^\r\n]+") do
            if line and line:match("%S") then
                first_line = line:gsub("^%s*#%s*", ""):gsub("^%s*", "")
                break
            end
        end
        
        -- Limit summary length
        if #first_line > 50 then
            return first_line:sub(1, 47) .. "..."
        else
            return first_line
        end
    end
    
    -- Parse and extract note links in a string (using [[note-title]] syntax)
    function M.parse_note_links(text)
        if not text or text == "" then
            return {}
        end
        
        local links = {}
        for link in text:gmatch("%[%[([^%]]+)%]%]") do
            table.insert(links, link)
        end
        return links
    end
    
    -- Find a note by title pattern (for linking)
    function M.find_note_by_title(title_pattern)
        if not title_pattern or title_pattern == "" then
            return nil
        end
        
        -- Normalize the title pattern for case-insensitive matching
        local pattern = title_pattern:lower()
        
        -- Check global notes first
        if M.notes.global and M.notes.global.content then
            local summary = M.generate_summary(M.notes.global.content)
            if summary:lower():find(pattern, 1, true) then
                return M.notes.global
            end
        end
        
        -- Check project notes
        for _, note in pairs(M.notes.project) do
            if note and note.content then
                local summary = M.generate_summary(note.content)
                if summary:lower():find(pattern, 1, true) then
                    return note
                end
            end
        end
        
        return nil
    end
    
    -- Get all available notes for link autocomplete
    function M.get_all_notes_titles()
        local titles = {}
        
        -- Add global note if available
        if M.notes.global and M.notes.global.content and M.notes.global.content ~= "" then
            local summary = M.generate_summary(M.notes.global.content)
            if summary ~= "" then
                table.insert(titles, {
                    id = M.notes.global.id,
                    title = summary,
                    mode = "global"
                })
            end
        end
        
        -- Add project notes
        for project_id, note in pairs(M.notes.project) do
            if note and note.content and note.content ~= "" then
                local summary = M.generate_summary(note.content)
                if summary ~= "" then
                    table.insert(titles, {
                        id = note.id,
                        title = summary,
                        mode = "project",
                        project = project_id
                    })
                end
            end
        end
        
        return titles
    end
    
    -- Get the current project identifier
    function M.get_current_project()
        local core = require("doit.core")
        local project_utils = nil
        
        if core.utils and core.utils.project then
            project_utils = core.utils.project
        else
            -- Fall back to directly requiring the project utils
            project_utils = require("doit.core.utils.project")
        end
        
        if project_utils and project_utils.get_identifier then
            return project_utils.get_identifier()
        else
            return vim.fn.getcwd()
        end
    end
    
    -- Generate a unique ID for a note
    function M.generate_note_id()
        return os.time() .. "_" .. math.random(1000000, 9999999)
    end
    
    return M
end

return M