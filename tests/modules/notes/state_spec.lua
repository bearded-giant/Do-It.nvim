local notes_module = require("doit.state.notes")
local config = require("doit.config")

-- Set up default config
config.setup({})

describe("notes", function()
    before_each(function()
        -- Reset notes state before each test
        notes_module.notes = {
            global = { content = "" },
            project = {},
            current_mode = "project",
        }
    end)

    it("should initialize with default values", function()
        assert.are.same({ content = "" }, notes_module.notes.global)
        assert.are.same({}, notes_module.notes.project)
        assert.are.equal("project", notes_module.notes.current_mode)
    end)

    it("should switch between global and project modes", function()
        -- Initial mode should be project
        assert.are.equal("project", notes_module.notes.current_mode)
        
        -- Switch to global
        notes_module.switch_mode()
        assert.are.equal("global", notes_module.notes.current_mode)
        
        -- Switch back to project
        notes_module.switch_mode()
        assert.are.equal("project", notes_module.notes.current_mode)
    end)

    it("should get the correct storage path", function()
        local base_path = config.options.notes.storage_path or vim.fn.stdpath("data") .. "/doit/notes"
        
        -- Global path
        local global_path = notes_module.get_storage_path(true)
        assert.are.equal(base_path .. "/global.json", global_path)
        
        -- For project path, we would need to mock project_identifier, but we can
        -- at least verify the function doesn't error
        local project_path = notes_module.get_storage_path(false)
        assert.is_not_nil(project_path)
    end)

    it("should save and retrieve notes content", function()
        -- Use in-memory operations to avoid file system access in tests
        local test_content = { content = "Test note content" }
        
        -- Set global notes
        notes_module.notes.current_mode = "global"
        notes_module.notes.global = test_content
        
        -- Get current notes should return global content
        local current = notes_module.get_current_notes()
        assert.are.same(test_content, current)
        
        -- Set project notes
        notes_module.notes.current_mode = "project"
        local project_id = "test-project"
        notes_module.notes.project[project_id] = { content = "Project-specific notes" }
        
        -- Mock the local get_project_identifier function
        -- First, redefine it in package.loaded to make it accessible for mocking
        package.loaded["doit.state"] = package.loaded["doit.state"] or {}
        package.loaded["doit.state"].get_project_identifier = function() 
            return project_id 
        end
        
        -- Get current notes should return project content
        current = notes_module.get_current_notes()
        assert.are.same({ content = "Project-specific notes" }, current)
    end)
end)