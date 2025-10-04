-- Simple test runner for obsidian-sync module
-- Run with: nvim --headless -l tests/modules/obsidian-sync/run_simple_test.lua

-- Add the plugin to the runtime path
vim.opt.runtimepath:append(vim.fn.getcwd())

-- Basic test assertions
local test_count = 0
local pass_count = 0
local fail_count = 0

local function assert_equals(expected, actual, message)
    test_count = test_count + 1
    if expected == actual then
        pass_count = pass_count + 1
        print("✓ " .. (message or "Test passed"))
        return true
    else
        fail_count = fail_count + 1
        print("✗ " .. (message or "Test failed"))
        print("  Expected: " .. tostring(expected))
        print("  Got: " .. tostring(actual))
        return false
    end
end

local function assert_true(value, message)
    return assert_equals(true, value, message)
end

local function assert_not_nil(value, message)
    test_count = test_count + 1
    if value ~= nil then
        pass_count = pass_count + 1
        print("✓ " .. (message or "Value is not nil"))
        return true
    else
        fail_count = fail_count + 1
        print("✗ " .. (message or "Value is nil"))
        return false
    end
end

print("========================================")
print("Testing obsidian-sync module")
print("========================================")
print("")

-- Mock dependencies
package.loaded["doit.core"] = {
    get_module = function(name)
        if name == "todos" then
            return {
                state = {
                    todos = {},
                    todo_lists = { active = "default" },
                    add_todo = function(text)
                        local todo = {
                            id = "test_" .. os.time(),
                            text = text,
                            done = false
                        }
                        table.insert(package.loaded["doit.core"].get_module("todos").state.todos, todo)
                        return todo
                    end,
                    get_available_lists = function()
                        return {{name = "default"}}
                    end,
                    create_list = function() return true end,
                    load_list = function() return true end
                }
            }
        end
        return nil
    end,
    register_module = function() end
}

package.loaded["obsidian"] = {
    get_client = function() return nil end
}

-- Test 1: Module loading
print("Test 1: Module loading")
local ok, obsidian_sync = pcall(require, "doit.modules.obsidian-sync")
assert_true(ok, "Module loads without error")
assert_not_nil(obsidian_sync, "Module is not nil")
assert_equals("1.0.0", obsidian_sync.version, "Version is correct")

-- Test 2: Module setup
print("\nTest 2: Module setup")
local setup_result = obsidian_sync.setup({
    vault_path = "~/TestVault",
    default_list = "test_list"
})
assert_not_nil(setup_result, "Setup returns result")
assert_equals("~/TestVault", obsidian_sync.config.vault_path, "Custom vault path set")
assert_equals("test_list", obsidian_sync.config.default_list, "Custom default list set")

-- Test 3: Keymaps configuration
print("\nTest 3: Keymaps configuration")
assert_equals("<leader>ti", obsidian_sync.config.keymaps.import_buffer, "Default import keymap")
assert_equals("<leader>tt", obsidian_sync.config.keymaps.send_current, "Default send keymap")

-- Test 4: List determination
print("\nTest 4: List determination")
obsidian_sync.setup_functions()
local daily_list = obsidian_sync.determine_list("/Users/test/Recharge-Notes/daily/test.md", "Task")
assert_equals("daily", daily_list, "Daily folder maps to daily list")

local inbox_list = obsidian_sync.determine_list("/Users/test/Recharge-Notes/inbox/test.md", "Task")
assert_equals("inbox", inbox_list, "Inbox folder maps to inbox list")

-- Test 5: Sync completion state logic
print("\nTest 5: Sync completion state logic")
-- Test buffer for sync tests
local test_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {"- [ ] Test todo"})

obsidian_sync.refs["test_id"] = {
    bufnr = test_buf,
    lnum = 1,
    file = "/test/file.md"
}

-- Test completed state
obsidian_sync.sync_completion("test_id", {done = true, in_progress = false})
local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
assert_equals("- [x] Test todo", lines[1], "Completed todo shows [x]")

-- Test in progress state
vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {"- [ ] Test todo"})
obsidian_sync.sync_completion("test_id", {done = false, in_progress = true})
lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
assert_equals("- [ ] Test todo", lines[1], "In-progress todo stays [ ]")

-- Clean up
vim.api.nvim_buf_delete(test_buf, {force = true})

-- Summary
print("\n========================================")
print("Test Results:")
print("  Total: " .. test_count)
print("  Passed: " .. pass_count)
print("  Failed: " .. fail_count)
print("========================================")

if fail_count == 0 then
    print("\n✓ All tests passed!")
    os.exit(0)
else
    print("\n✗ Some tests failed")
    os.exit(1)
end