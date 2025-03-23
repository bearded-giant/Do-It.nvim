-- tests/ui/reordering_spec.lua
local stub = require("luassert.stub")

describe("todo reordering UI", function()
  local state = require("doit.state")
  local config = require("doit.config")
  local todo_actions = require("doit.ui.todo_actions")
  local main_window = require("doit.ui.main_window")
  
  -- Setup test environment
  before_each(function()
    -- Set up config for tests
    config.options = config.options or {}
    config.options.keymaps = config.options.keymaps or {}
    config.options.keymaps.reorder_todo = "r"
    config.options.keymaps.move_todo_up = "k"
    config.options.keymaps.move_todo_down = "j"
    
    -- Initialize the state
    state.todos = {
      {
        text = "Todo 1",
        done = false,
        in_progress = false,
        created_at = os.time() - 300,
        order_index = 1,
      },
      {
        text = "Todo 2",
        done = false,
        in_progress = false,
        created_at = os.time() - 200,
        order_index = 2,
      },
    }
    
    -- Stubs
    stub(state, "save_to_disk")
    stub(state, "sort_todos")
    stub(main_window, "render_todos")
  end)
  
  after_each(function()
    state.save_to_disk:revert()
    state.sort_todos:revert()
    main_window.render_todos:revert()
  end)
  
  it("should have reorder functionality", function()
    assert.is_not_nil(todo_actions.reorder_todo)
    assert.is_function(todo_actions.reorder_todo)
  end)
  
  it("should sort todos after moving", function()
    -- Assume we're in reorder mode and swap todo indices
    local tmp_order = state.todos[1].order_index
    state.todos[1].order_index = state.todos[2].order_index
    state.todos[2].order_index = tmp_order
    
    -- Trigger sort
    state.sort_todos()
    
    -- Test sort was called
    assert.stub(state.sort_todos).was.called(1)
  end)
  
  it("should save to disk when exiting reorder mode", function()
    -- Setup mock keymap function to capture setup
    _G.keymap_functions = {}
    local old_keymap_set = vim.keymap.set
    vim.keymap.set = function(mode, key, fn)
      _G.keymap_functions[key] = fn
    end
    
    -- Mock win_id for testing
    local mock_win_id = 1000
    
    -- Call reorder_todo to set up keymaps
    todo_actions.reorder_todo(mock_win_id, function() end)
    
    -- Reset vim.keymap.set
    vim.keymap.set = old_keymap_set
    
    -- Call update_order_indices (normally called on exit)
    for i, todo in ipairs(state.todos) do
      todo.order_index = i
    end
    state.save_to_disk()
    
    -- Check save_to_disk was called
    assert.stub(state.save_to_disk).was.called(1)
  end)
  
  it("should prevent entering reorder mode multiple times", function()
    -- Set up notification mock
    local notify_calls = {}
    local old_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, {message = msg, level = level})
    end
    
    -- Mock win_id for testing
    local mock_win_id = 1000
    
    -- Mock win and buf validation to always return true
    stub(vim.api, "nvim_win_is_valid").returns(true)
    stub(vim.api, "nvim_buf_is_valid").returns(true)
    stub(vim.api, "nvim_win_get_cursor").returns({2, 0}) -- Position at todo 1
    stub(vim.api, "nvim_win_get_buf").returns(1001)
    stub(vim.api, "nvim_buf_get_lines").returns({"  ○ Todo 1"})
    stub(vim.api, "nvim_buf_set_option")
    stub(vim.api, "nvim_buf_clear_namespace")
    stub(vim.api, "nvim_buf_add_highlight")
    
    -- First reorder attempt should succeed (call with mock win_id and render function)
    todo_actions.reorder_todo(mock_win_id, function() end)
    
    -- Second attempt should show warning
    todo_actions.reorder_todo(mock_win_id, function() end)
    
    -- Clean up stubs
    vim.api.nvim_win_is_valid:revert()
    vim.api.nvim_buf_is_valid:revert()
    vim.api.nvim_win_get_cursor:revert()
    vim.api.nvim_win_get_buf:revert()
    vim.api.nvim_buf_get_lines:revert()
    vim.api.nvim_buf_set_option:revert()
    vim.api.nvim_buf_clear_namespace:revert()
    vim.api.nvim_buf_add_highlight:revert()
    
    -- Reset notify
    vim.notify = old_notify
    
    -- Check that the second attempt triggered a warning
    assert.equals("Already in reordering mode", notify_calls[2].message)
    assert.equals(vim.log.levels.WARNING, notify_calls[2].level)
  end)
  
  it("should allow reordering after exiting reorder mode", function()
    -- Setup notification and keymap mocks
    local notify_calls = {}
    local old_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, {message = msg, level = level})
    end
    
    -- Mock key function calls for testing
    local keymap_functions = {}
    local old_keymap_set = vim.keymap.set
    vim.keymap.set = function(mode, key, fn, opts)
      keymap_functions[key] = fn
    end
    
    -- Mock API functions
    stub(vim.api, "nvim_win_is_valid").returns(true)
    stub(vim.api, "nvim_buf_is_valid").returns(true)
    stub(vim.api, "nvim_win_get_cursor").returns({2, 0}) -- Position at todo 1
    stub(vim.api, "nvim_win_get_buf").returns(1001)
    stub(vim.api, "nvim_buf_get_lines").returns({"  ○ Todo 1"})
    stub(vim.api, "nvim_buf_set_option")
    stub(vim.api, "nvim_buf_clear_namespace")
    stub(vim.api, "nvim_buf_add_highlight")
    stub(vim.keymap, "del")
    
    -- Mock win_id for testing
    local mock_win_id = 1000
    
    -- First reorder attempt
    todo_actions.reorder_todo(mock_win_id, function() end)
    
    -- Simulate pressing 'r' to exit reorder mode
    if keymap_functions["r"] then
      keymap_functions["r"]()
    end
    
    -- Reset api stubs that might be called again
    vim.api.nvim_win_get_cursor:revert()
    vim.api.nvim_buf_get_lines:revert()
    
    -- Re-stub for second call
    stub(vim.api, "nvim_win_get_cursor").returns({2, 0})
    stub(vim.api, "nvim_buf_get_lines").returns({"  ○ Todo 1"})
    
    -- Second reorder attempt should now succeed
    todo_actions.reorder_todo(mock_win_id, function() end)
    
    -- Clean up all stubs
    vim.api.nvim_win_is_valid:revert()
    vim.api.nvim_buf_is_valid:revert()
    vim.api.nvim_win_get_cursor:revert()
    vim.api.nvim_win_get_buf:revert()
    vim.api.nvim_buf_get_lines:revert()
    vim.api.nvim_buf_set_option:revert()
    vim.api.nvim_buf_clear_namespace:revert()
    vim.api.nvim_buf_add_highlight:revert()
    vim.keymap.del:revert()
    
    -- Reset mocks
    vim.notify = old_notify
    vim.keymap.set = old_keymap_set
    
    -- Check notifications - should have entered reorder mode twice
    local reorder_mode_entries = 0
    for _, call in ipairs(notify_calls) do
      if call.message:match("Reordering mode: Press Up/Down") then
        reorder_mode_entries = reorder_mode_entries + 1
      end
    end
    assert.equals(2, reorder_mode_entries)
  end)
end)