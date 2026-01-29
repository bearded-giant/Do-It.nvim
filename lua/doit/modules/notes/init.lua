-- notes module for doit.nvim
local M = {}

M.version = "2.0.0"

M.metadata = {
    name = "notes",
    version = M.version,
    description = "Multi-note management with picker, CRUD, and sorting",
    author = "bearded-giant",
    path = "doit.modules.notes",
    dependencies = {},
    config_schema = {
        enabled = { type = "boolean", default = true },
        storage = { type = "table" },
        keymaps = { type = "table" },
    },
}

function M.setup(opts)
    local core = require("doit.core")

    local config = require("doit.modules.notes.config")
    M.config = config.setup(opts)

    local state_module = require("doit.modules.notes.state")
    M.state = state_module.setup(M)

    local ui_module = require("doit.modules.notes.ui")
    M.ui = ui_module.setup(M)

    M.commands = require("doit.modules.notes.commands").setup(M)

    core.register_module("notes", M)

    M.setup_keymaps()

    M.on_note_created = function(note)
        core.events.emit("note_created", {
            id = note.id,
            title = note.title,
            summary = M.state.generate_summary(note.body or ""),
            metadata = note.metadata or {},
            project = M.state.get_current_project(),
        })
    end

    M.on_note_updated = function(note)
        core.events.emit("note_updated", {
            id = note.id,
            title = note.title,
            summary = M.state.generate_summary(note.body or ""),
            metadata = note.metadata or {},
            project = M.state.get_current_project(),
        })
    end

    M.on_note_deleted = function(note)
        core.events.emit("note_deleted", {
            id = note.id,
            metadata = note.metadata or {},
        })
    end

    return M
end

function M.setup_keymaps()
    local config = M.config
    if config.keymaps.toggle then
        vim.keymap.set("n", config.keymaps.toggle, function()
            M.ui.notes_picker.toggle()
        end, { desc = "Toggle Notes Picker" })
    end
end

function M.standalone_setup(opts)
    if not package.loaded["doit.core"] then
        local minimal_core = {
            register_module = function() return end,
            get_module = function() return nil end,
            events = {
                on = function() return function() end end,
                emit = function() return end,
            },
        }
        package.loaded["doit.core"] = minimal_core
    end
    return M.setup(opts)
end

return M
