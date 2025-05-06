-- Todos module for doit.nvim
local M = {}

-- Module version
M.version = "2.0.0"

-- Module metadata for registry
M.metadata = {
    name = "todos",
    version = M.version,
    description = "Todo management with support for priorities, due dates, and multiple lists",
    author = "bearded-giant",
    path = "doit.modules.todos",
    dependencies = {},
    config_schema = {
        enabled = { type = "boolean", default = true },
        save_path = { type = "string" },
        window = { type = "table" },
        formatting = { type = "table" },
        keymaps = { type = "table" }
    }
}

-- Setup function for the todos module
function M.setup(opts)
    -- Initialize module with core framework
    local core = require("doit.core")
    
    -- Setup module configuration
    local config = require("doit.modules.todos.config")
    M.config = config.setup(opts)
    
    -- Initialize state with module reference
    local state_module = require("doit.modules.todos.state")
    M.state = state_module.setup(M)
    M.state.load_todos()
    
    -- Initialize UI with module reference
    local ui_module = require("doit.modules.todos.ui")
    M.ui = ui_module.setup(M)
    
    -- Initialize commands
    M.commands = require("doit.modules.todos.commands").setup(M)
    
    -- Register module with core
    core.register_module("todos", M)
    
    -- Set up keymaps from config
    M.setup_keymaps()
    
    -- Listen for events from other modules if they exist
    if core.get_module("notes") then
        -- Listen for note updates to sync linked todos
        core.events.on("note_updated", function(data)
            if data and data.id then
                -- Update any todos linked to this note
                local linked_todos = M.state.get_todos_by_note_id(data.id)
                if linked_todos and #linked_todos > 0 then
                    -- Update the linked todos with the latest note information
                    for _, todo in ipairs(linked_todos) do
                        todo.note_summary = data.summary or data.title or "Linked note"
                        todo.note_updated_at = os.time()
                    end
                    M.state.save_todos()
                    
                    -- Emit event for UI to refresh
                    core.events.emit("todos_updated", { 
                        reason = "note_updated",
                        note_id = data.id 
                    })
                end
            end
        end)
        
        -- Listen for note creation to potentially link to todos
        core.events.on("note_created", function(data)
            if data and data.id and data.metadata and data.metadata.todo_id then
                -- Link this note to an existing todo
                local todo_id = data.metadata.todo_id
                local todo = M.state.get_todo_by_id(todo_id)
                if todo then
                    todo.note_id = data.id
                    todo.note_summary = data.summary or data.title or "Linked note"
                    todo.note_updated_at = os.time()
                    M.state.save_todos()
                    
                    -- Emit event for UI to refresh
                    core.events.emit("todos_updated", { 
                        reason = "note_linked",
                        todo_id = todo_id,
                        note_id = data.id 
                    })
                end
            end
        end)
        
        -- Listen for note deletion to unlink from todos
        core.events.on("note_deleted", function(data)
            if data and data.id then
                -- Unlink any todos linked to this note
                local linked_todos = M.state.get_todos_by_note_id(data.id)
                if linked_todos and #linked_todos > 0 then
                    for _, todo in ipairs(linked_todos) do
                        todo.note_id = nil
                        todo.note_summary = nil
                        todo.note_updated_at = nil
                    end
                    M.state.save_todos()
                    
                    -- Emit event for UI to refresh
                    core.events.emit("todos_updated", { 
                        reason = "note_deleted",
                        note_id = data.id 
                    })
                end
            end
        end)
    end
    
    -- Emit events for todos that other modules can listen to
    M.emit_events = true
    
    return M
end

-- Set up module keymaps
function M.setup_keymaps()
    local config = M.config
    
    -- Main window toggle
    if config.keymaps.toggle_window then
        vim.keymap.set("n", config.keymaps.toggle_window, function()
            M.ui.main_window.toggle_todo_window()
        end, { desc = "Toggle Todo List" })
    end
    
    -- List window toggle
    if config.keymaps.toggle_list_window then
        vim.keymap.set("n", config.keymaps.toggle_list_window, function()
            M.ui.list_window.toggle_list_window()
        end, { desc = "Toggle Active Todo List" })
    end
end

-- Standalone entry point (when used without the framework)
function M.standalone_setup(opts)
    -- Create minimal core if it doesn't exist
    if not package.loaded["doit.core"] then
        -- Minimal core implementation
        local minimal_core = {
            register_module = function() return end,
            get_module = function() return nil end,
            events = {
                on = function() return function() end end,
                emit = function() return end
            }
        }
        package.loaded["doit.core"] = minimal_core
    end
    
    return M.setup(opts)
end

return M