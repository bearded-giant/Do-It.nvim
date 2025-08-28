-- Full configuration for testing in Docker container
return {
  -- Core framework configuration
  development_mode = true,
  quick_keys = true,
  timestamp = {
    enabled = true,
  },
  lualine = {
    enabled = true,
    max_length = 30,
  },
  project = {
    enabled = true,
    detection = {
      use_git = true,
      fallback_to_cwd = true,
    },
    storage = {
      path = vim.fn.stdpath("data") .. "/doit/projects",
    },
  },
  
  -- Module configurations
  modules = {
    -- Todo module configuration
    todos = {
      enabled = true,
      ui = {
        window = {
          width = 55,
          height = 20,
          border = "rounded",
          position = "center",
          padding = {
            top = 1,
            bottom = 1,
            left = 2,
            right = 2,
          },
        },
        list_window = {
          width = 40,
          height = 10,
          position = "bottom-right",
        },
        calendar = {
          language = "en",
          icon = "",
          keymaps = {
            previous_day = "h",
            next_day = "l",
            previous_week = "k",
            next_week = "j",
            previous_month = "H",
            next_month = "L",
            select_day = "<CR>",
            close_calendar = "q",
          },
        },
        scratchpad = {
          syntax_highlight = "markdown",
        },
        list_manager = {
          preview_enabled = true,
          width_ratio = 0.8,
          height_ratio = 0.8,
          list_panel_ratio = 0.4,
        },
      },
      formatting = {
        pending = {
          icon = "○",
          format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
        },
        in_progress = {
          icon = "◐",
          format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
        },
        done = {
          icon = "✓",
          format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
        },
      },
      priorities = {
        { name = "critical", weight = 16 },
        { name = "urgent", weight = 8 },
        { name = "important", weight = 4 },
      },
      priority_groups = {
        critical = {
          members = { "critical" },
          color = "#FF0000",
        },
        high = {
          members = { "urgent" },
          color = nil,
          hl_group = "DiagnosticWarn",
        },
        medium = {
          members = { "important" },
          color = nil,
          hl_group = "DiagnosticInfo",
        },
        low = {
          members = {},
          color = "#FFFFFF",
        },
      },
      hour_score_value = 1 / 8,
      storage = {
        save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
        import_export_path = vim.fn.expand("~/todos.json"),
      },
      keymaps = {
        toggle_window = "<leader>do",
        toggle_list_window = "<leader>dl",
        new_todo = "i",
        toggle_todo = "x",
        delete_todo = "d",
        delete_completed = "D",
        delete_confirmation = "<Y>",
        close_window = "q",
        undo_delete = "u",
        add_due_date = "H",
        remove_due_date = "r",
        toggle_help = "?",
        toggle_tags = "t",
        toggle_categories = "C",
        toggle_priority = "<Space>",
        clear_filter = "c",
        edit_todo = "e",
        edit_tag = "e",
        edit_priorities = "p",
        delete_tag = "d",
        share_todos = "s",
        search_todos = "/",
        add_time_estimation = "T",
        remove_time_estimation = "R",
        import_todos = "I",
        export_todos = "E",
        remove_duplicates = "<leader>D",
        open_todo_scratchpad = "<leader>p",
        reorder_todo = "r",
        move_todo_up = "k",
        move_todo_down = "j",
        open_linked_note = "o",
      },
    },
    
    -- Notes module configuration
    notes = {
      enabled = true,
      ui = {
        window = {
          -- Testing both absolute and relative sizing
          width = 80,  -- Absolute width in columns
          height = 30, -- Absolute height in lines
          border = "rounded",
          title = " Notes ",
          title_pos = "center",
          position = "center",
          relative_width = 0.6,  -- 60% of screen width
          relative_height = 0.6, -- 60% of screen height
          use_relative = true,   -- Toggle to test both modes
        },
        icons = {
          note = "📓",
          linked = "🔗",
        },
      },
      storage = {
        path = vim.fn.stdpath("data") .. "/doit/notes",
        mode = "project", -- "global" or "project"
      },
      markdown = {
        highlight = true,
        syntax = "markdown",
        conceallevel = 2,
        concealcursor = "nc",
        extensions = true,
      },
      keymaps = {
        toggle = "<leader>dn",
        close = "q",
        switch_mode = "m",
        -- Markdown editing keymaps
        format = "gq",
        heading1 = "<leader>1",
        heading2 = "<leader>2",
        heading3 = "<leader>3",
        bold = "<leader>b",
        italic = "<leader>i",
        link = "<leader>l",
        list_item = "<leader>-",
      },
    },
  },
  
  -- Legacy configuration (for backward compatibility testing)
  window = {
    width = 55,
    height = 20,
    border = "rounded",
    position = "center",
    padding = {
      top = 1,
      bottom = 1,
      left = 2,
      right = 2,
    },
  },
  list_window = {
    width = 40,
    height = 10,
    position = "bottom-right",
  },
  notes = {
    enabled = true,
    icon = "📓",
    linked_icon = "🔗",
    storage_path = vim.fn.stdpath("data") .. "/doit/notes",
    mode = "project",
    window = {
      width = 0.6,
      height = 0.6,
      border = "rounded",
      title = " Notes ",
      title_pos = "center",
    },
    keymaps = {
      toggle = "<leader>dn",
      close = "q",
      switch_mode = "m",
    },
  },
  formatting = {
    pending = {
      icon = "○",
      format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
    },
    in_progress = {
      icon = "◐",
      format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
    },
    done = {
      icon = "✓",
      format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
    },
  },
  priorities = {
    { name = "critical", weight = 16 },
    { name = "urgent", weight = 8 },
    { name = "important", weight = 4 },
  },
  priority_groups = {
    critical = {
      members = { "critical" },
      color = "#FF0000",
    },
    high = {
      members = { "urgent" },
      color = nil,
      hl_group = "DiagnosticWarn",
    },
    medium = {
      members = { "important" },
      color = nil,
      hl_group = "DiagnosticInfo",
    },
    low = {
      members = {},
      color = "#FFFFFF",
    },
  },
  hour_score_value = 1 / 8,
  save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
  import_export_path = vim.fn.expand("~/todos.json"),
  keymaps = {
    toggle_window = "<leader>do",
    toggle_list_window = "<leader>dl",
    new_todo = "i",
    toggle_todo = "x",
    delete_todo = "d",
    delete_completed = "D",
    delete_confirmation = "<Y>",
    close_window = "q",
    undo_delete = "u",
    add_due_date = "H",
    remove_due_date = "r",
    toggle_help = "?",
    toggle_tags = "t",
    toggle_categories = "C",
    toggle_priority = "<Space>",
    clear_filter = "c",
    edit_todo = "e",
    edit_tag = "e",
    edit_priorities = "p",
    delete_tag = "d",
    share_todos = "s",
    search_todos = "/",
    add_time_estimation = "T",
    remove_time_estimation = "R",
    import_todos = "I",
    export_todos = "E",
    remove_duplicates = "<leader>D",
    open_todo_scratchpad = "<leader>p",
    reorder_todo = "r",
    move_todo_up = "k",
    move_todo_down = "j",
    open_linked_note = "o",
  },
  calendar = {
    language = "en",
    icon = "",
    keymaps = {
      previous_day = "h",
      next_day = "l",
      previous_week = "k",
      next_week = "j",
      previous_month = "H",
      next_month = "L",
      select_day = "<CR>",
      close_calendar = "q",
    },
  },
  scratchpad = {
    syntax_highlight = "markdown",
  },
}