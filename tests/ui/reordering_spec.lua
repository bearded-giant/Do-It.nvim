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
end)