local M = {}

-- sort modes: 1=created_at desc, 2=title asc, 3=created_at asc
local SORT_CREATED_DESC = 1
local SORT_TITLE_ASC = 2
local SORT_CREATED_ASC = 3

function M.setup(parent_module)
    local storage = require("doit.modules.notes.state.storage")

    storage.setup(M, parent_module)

    for name, func in pairs(storage) do
        if type(func) == "function" and not M[name] then
            M[name] = func
        end
    end

    local cfg = parent_module and parent_module.config or {}
    local storage_cfg = cfg.storage or cfg
    local initial_mode = storage_cfg.mode or cfg.mode or "project"

    M.notes = {
        global = {},
        project = {},
        current_mode = initial_mode,
        sort_mode = SORT_CREATED_DESC,
        search_filter = nil,
    }

    function M.generate_note_id()
        return os.time() .. "_" .. math.random(1000000, 9999999)
    end

    function M.create_note(title)
        if not title or title == "" then return nil end

        local note = {
            id = M.generate_note_id(),
            title = title,
            body = "",
            created_at = os.time(),
            updated_at = os.time(),
            scope = M.notes.current_mode,
            project_id = nil,
        }
        if M.notes.current_mode == "project" then
            note.project_id = M.get_project_identifier()
        end

        M.save_note(note)
        return note
    end

    function M.sort_notes(notes_list)
        if not notes_list or #notes_list == 0 then return notes_list end

        local sorted = {}
        for _, n in ipairs(notes_list) do
            table.insert(sorted, n)
        end

        local mode = M.notes.sort_mode or SORT_CREATED_DESC

        if mode == SORT_CREATED_DESC then
            table.sort(sorted, function(a, b)
                return (a.created_at or 0) > (b.created_at or 0)
            end)
        elseif mode == SORT_TITLE_ASC then
            table.sort(sorted, function(a, b)
                return (a.title or ""):lower() < (b.title or ""):lower()
            end)
        elseif mode == SORT_CREATED_ASC then
            table.sort(sorted, function(a, b)
                return (a.created_at or 0) < (b.created_at or 0)
            end)
        end

        return sorted
    end

    function M.cycle_sort()
        local mode = M.notes.sort_mode or SORT_CREATED_DESC
        if mode == SORT_CREATED_DESC then
            M.notes.sort_mode = SORT_TITLE_ASC
        elseif mode == SORT_TITLE_ASC then
            M.notes.sort_mode = SORT_CREATED_ASC
        else
            M.notes.sort_mode = SORT_CREATED_DESC
        end
        return M.notes.sort_mode
    end

    function M.get_sort_label()
        local mode = M.notes.sort_mode or SORT_CREATED_DESC
        if mode == SORT_CREATED_DESC then return "date (newest)" end
        if mode == SORT_TITLE_ASC then return "title (a-z)" end
        return "date (oldest)"
    end

    function M.filter_notes(notes_list, query)
        if not query or query == "" then return notes_list end

        local filtered = {}
        local q = query:lower()
        for _, n in ipairs(notes_list) do
            if (n.title or ""):lower():find(q, 1, true) then
                table.insert(filtered, n)
            end
        end
        return filtered
    end

    function M.get_sorted_filtered_notes()
        local list = M.get_current_notes_list()
        list = M.sort_notes(list)
        if M.notes.search_filter then
            list = M.filter_notes(list, M.notes.search_filter)
        end
        return list
    end

    function M.get_note_by_id(note_id)
        local list = M.get_current_notes_list()
        for _, n in ipairs(list) do
            if n.id == note_id then
                return n
            end
        end
        return nil
    end

    function M.relative_time(timestamp)
        if not timestamp then return "" end
        local diff = os.time() - timestamp
        if diff < 60 then return "just now" end
        if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
        if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
        if diff < 604800 then return math.floor(diff / 86400) .. "d ago" end
        if diff < 2592000 then return math.floor(diff / 604800) .. "w ago" end
        return os.date("%Y-%m-%d", timestamp)
    end

    function M.get_current_project()
        local core = require("doit.core")
        if core.utils and core.utils.project then
            return core.utils.project.get_identifier()
        end
        return vim.fn.getcwd()
    end

    -- legacy compat
    function M.generate_summary(content)
        if not content or content == "" then return "" end
        local first_line = ""
        for line in content:gmatch("[^\r\n]+") do
            if line and line:match("%S") then
                first_line = line:gsub("^%s*#%s*", ""):gsub("^%s*", "")
                break
            end
        end
        if #first_line > 50 then
            return first_line:sub(1, 47) .. "..."
        end
        return first_line
    end

    function M.parse_note_links(text)
        if not text or text == "" then return {} end
        local links = {}
        for link in text:gmatch("%[%[([^%]]+)%]%]") do
            table.insert(links, link)
        end
        return links
    end

    return M
end

return M
