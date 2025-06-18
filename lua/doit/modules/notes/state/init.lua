local M = {}

function M.setup(parent_module)
    local storage = require("doit.modules.notes.state.storage")
    
    storage.setup(M, parent_module)
    
    for name, func in pairs(storage) do
        if type(func) == "function" and not M[name] then
            M[name] = func
        end
    end
    
    M.notes = {
        global = { content = "" },
        project = {},
        current_mode = "project",
    }
    
    function M.generate_summary(content)
        if not content or content == "" then
            return ""
        end
        
        local first_line = ""
        for line in content:gmatch("[^\r\n]+") do
            if line and line:match("%S") then
                first_line = line:gsub("^%s*#%s*", ""):gsub("^%s*", "")
                break
            end
        end
        
        if #first_line > 50 then
            return first_line:sub(1, 47) .. "..."
        else
            return first_line
        end
    end
    
    -- Parse [[note-title]] syntax links
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
    
    function M.find_note_by_title(title_pattern)
        if not title_pattern or title_pattern == "" then
            return nil
        end
        
        local pattern = title_pattern:lower()
        
        if M.notes.global and M.notes.global.content then
            local summary = M.generate_summary(M.notes.global.content)
            if summary:lower():find(pattern, 1, true) then
                return M.notes.global
            end
        end
        
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
    
    function M.get_all_notes_titles()
        local titles = {}
        
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
    
    function M.get_current_project()
        local core = require("doit.core")
        local project_utils = nil
        
        if core.utils and core.utils.project then
            project_utils = core.utils.project
        else
            project_utils = require("doit.core.utils.project")
        end
        
        if project_utils and project_utils.get_identifier then
            return project_utils.get_identifier()
        else
            return vim.fn.getcwd()
        end
    end
    
    function M.generate_note_id()
        return os.time() .. "_" .. math.random(1000000, 9999999)
    end
    
    return M
end

return M