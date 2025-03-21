local dooing_state = require("dooing.state")
local storage = require("dooing.state.storage")
local config = require("dooing.config")
local mock_config = {
    options = {
        save_path = "/tmp/dooing_test_todos.json"
    }
}

-- Mock functions
local original_io_open = io.open
local mock_file = {
    write = function(self, content) self.content = content end,
    read = function(self) return self.content end,
    close = function() end,
    content = ""
}

describe("storage", function()
    before_each(function()
        -- Set up mocks
        _G.io.open = function(path, mode)
            if mode == "r" and not mock_file.content then
                return nil -- Simulate file not found for reading
            end
            return mock_file
        end

        -- Set up test state
        dooing_state.todos = {}
        
        -- Apply mock config
        config.options = mock_config.options
    end)

    after_each(function()
        -- Restore original functions
        _G.io.open = original_io_open
        mock_file.content = ""
    end)

    it("should save todos to disk", function()
        -- Set up test data
        dooing_state.todos = {
            {text = "Test todo", done = false, created_at = os.time()}
        }

        -- Mock vim.fn.json_encode
        local original_json_encode = vim.fn.json_encode
        vim.fn.json_encode = function(data)
            return '{"text":"Test todo","done":false}'
        end

        -- Call the function
        dooing_state.save_to_disk()

        -- Verify
        assert.are.equal('{"text":"Test todo","done":false}', mock_file.content)

        -- Restore original function
        vim.fn.json_encode = original_json_encode
    end)

    it("should load todos from disk", function()
        -- Set up test data in the mock file
        mock_file.content = '[{"text":"Loaded todo","done":false}]'

        -- Mock vim.fn.json_decode
        local original_json_decode = vim.fn.json_decode
        vim.fn.json_decode = function(content)
            return {{text = "Loaded todo", done = false}}
        end

        -- Call the function
        dooing_state.load_from_disk()

        -- Verify
        assert.are.equal("Loaded todo", dooing_state.todos[1].text)
        assert.are.equal(false, dooing_state.todos[1].done)

        -- Restore original function
        vim.fn.json_decode = original_json_decode
    end)

    it("should import todos from file", function()
        -- Set up test data in the mock file
        mock_file.content = '[{"text":"Imported todo","done":false}]'

        -- Set up existing todos
        dooing_state.todos = {{text = "Existing todo", done = false}}

        -- Mock vim.fn.json_decode
        local original_json_decode = vim.fn.json_decode
        vim.fn.json_decode = function(content)
            return {{text = "Imported todo", done = false}}
        end

        -- Mock sort_todos
        dooing_state.sort_todos = function() end

        -- Call the function
        local success, message = dooing_state.import_todos("/path/to/import.json")

        -- Verify
        assert.is_true(success)
        assert.are.equal(2, #dooing_state.todos)
        assert.are.equal("Existing todo", dooing_state.todos[1].text)
        assert.are.equal("Imported todo", dooing_state.todos[2].text)

        -- Restore original function
        vim.fn.json_decode = original_json_decode
    end)

    it("should export todos to file", function()
        -- Set up test data
        dooing_state.todos = {
            {text = "Todo to export", done = false, created_at = os.time()}
        }

        -- Mock vim.fn.json_encode
        local original_json_encode = vim.fn.json_encode
        vim.fn.json_encode = function(data)
            return '[{"text":"Todo to export","done":false}]'
        end

        -- Call the function
        local success, message = dooing_state.export_todos("/path/to/export.json")

        -- Verify
        assert.is_true(success)
        assert.are.equal('[{"text":"Todo to export","done":false}]', mock_file.content)

        -- Restore original function
        vim.fn.json_encode = original_json_encode
    end)
end)