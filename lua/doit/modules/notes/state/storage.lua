-- multi-note storage for notes module
local M = {}

function M.setup(state, parent_module)
    local config
    if parent_module and parent_module.config then
        config = parent_module.config
    else
        config = require("doit.modules.notes.config").options
    end

    function M.get_project_identifier()
        local ok, core = pcall(require, "doit.core")
        if ok and core.utils and core.utils.project then
            local id = core.utils.project.get_identifier()
            if id then return id end
        end
        local project_module = package.loaded["doit.state"] and package.loaded["doit.state"].get_project_identifier
        if project_module then
            local id = project_module()
            if id then return id end
        end
        -- fallback: hash cwd so project notes always get a unique file
        local cwd = vim.fn.getcwd()
        return string.sub(vim.fn.sha256(cwd), 1, 10)
    end

    function M.get_storage_path(is_global)
        local storage_config = config.storage or config
        local base_path = storage_config.path or storage_config.storage_path or vim.fn.stdpath("data") .. "/doit/notes"

        local mkdir_cmd = vim.fn.has("win32") == 1 and "mkdir" or "mkdir -p"
        vim.fn.system(mkdir_cmd .. " " .. vim.fn.shellescape(base_path))

        if not is_global then
            local project_id = M.get_project_identifier()
            if project_id then
                local hash = vim.fn.sha256(project_id)
                return base_path .. "/project-" .. string.sub(hash, 1, 10) .. ".json"
            end
        end

        return base_path .. "/global.json"
    end

    -- migrate old single-note format to new array format
    local function migrate_note(data)
        if type(data) ~= "table" then
            return {}
        end
        -- already an array
        if data[1] ~= nil or (not data.content and not data.body and not data.id) then
            return data
        end
        -- single note object -> wrap in array, rename content -> body
        local note = {
            id = data.id or state.generate_note_id(),
            title = data.title or "Untitled",
            body = data.body or data.content or "",
            created_at = data.created_at or os.time(),
            updated_at = data.updated_at or os.time(),
            scope = state.notes.current_mode,
            project_id = nil,
        }
        if state.notes.current_mode == "project" then
            note.project_id = M.get_project_identifier()
        end
        return { note }
    end

    -- load all notes for current scope
    function M.load_notes()
        local is_global = state.notes.current_mode == "global"
        local file_path = M.get_storage_path(is_global)
        local notes = {}

        local success, f = pcall(io.open, file_path, "r")
        if success and f then
            local raw = f:read("*all")
            f:close()
            if raw and raw ~= "" then
                local ok, data = pcall(vim.fn.json_decode, raw)
                if ok and data then
                    notes = migrate_note(data)
                end
            end
        end

        -- store in state
        if is_global then
            state.notes.global = notes
        else
            local project_id = M.get_project_identifier()
            if project_id then
                state.notes.project[project_id] = notes
            end
        end

        return notes
    end

    -- save all notes for current scope
    function M.save_notes_list(notes_list)
        if not notes_list then return false end

        local is_global = state.notes.current_mode == "global"
        local file_path = M.get_storage_path(is_global)

        local ok, f = pcall(io.open, file_path, "w")
        if ok and f then
            local status, json = pcall(vim.fn.json_encode, notes_list)
            if status then
                f:write(json)
                f:close()

                if is_global then
                    state.notes.global = notes_list
                else
                    local project_id = M.get_project_identifier()
                    if project_id then
                        state.notes.project[project_id] = notes_list
                    end
                end
                return true
            else
                f:close()
                vim.notify("error encoding notes data", vim.log.levels.ERROR)
                return false
            end
        else
            vim.notify("failed to save notes to file", vim.log.levels.ERROR)
            return false
        end
    end

    -- save a single note (update in-place or append)
    function M.save_note(note)
        if not note or not note.id then return false end

        local notes_list = M.get_current_notes_list()
        local found = false
        for i, n in ipairs(notes_list) do
            if n.id == note.id then
                note.updated_at = os.time()
                notes_list[i] = note
                found = true
                break
            end
        end
        if not found then
            table.insert(notes_list, note)
        end

        local ok = M.save_notes_list(notes_list)

        if ok and parent_module then
            if found and parent_module.on_note_updated then
                parent_module.on_note_updated(note)
            elseif not found and parent_module.on_note_created then
                parent_module.on_note_created(note)
            end
        end

        return ok
    end

    -- delete a note by id
    function M.delete_note(note_id)
        if not note_id then return false end

        local notes_list = M.get_current_notes_list()
        local deleted_note = nil
        for i, n in ipairs(notes_list) do
            if n.id == note_id then
                deleted_note = table.remove(notes_list, i)
                break
            end
        end

        if not deleted_note then return false end

        local ok = M.save_notes_list(notes_list)
        if ok and parent_module and parent_module.on_note_deleted then
            parent_module.on_note_deleted(deleted_note)
        end
        return ok
    end

    -- get notes list for current scope (from memory)
    function M.get_current_notes_list()
        if state.notes.current_mode == "global" then
            if not state.notes.global or #state.notes.global == 0 then
                return M.load_notes()
            end
            return state.notes.global
        else
            local project_id = M.get_project_identifier()
            if project_id and state.notes.project[project_id] and #state.notes.project[project_id] > 0 then
                return state.notes.project[project_id]
            end
            return M.load_notes()
        end
    end

    -- switch between global and project
    function M.switch_mode()
        if state.notes.current_mode == "global" then
            state.notes.current_mode = "project"
        else
            state.notes.current_mode = "global"
        end
        return M.load_notes()
    end

    -- legacy compat: save_notes wraps old single-note calls
    function M.save_notes(notes_content)
        if not notes_content then return false end
        -- old callers pass {content = "..."}, convert to new format
        if notes_content.content and not notes_content.body then
            notes_content.body = notes_content.content
            notes_content.content = nil
        end
        if notes_content.id then
            return M.save_note(notes_content)
        end
        -- no id means we can't identify which note, save as-is to list
        return false
    end

    -- legacy compat
    function M.get_current_notes()
        local list = M.get_current_notes_list()
        if #list > 0 then
            return list[1]
        end
        return { id = state.generate_note_id(), body = "", title = "Untitled" }
    end

    return M
end

return M
