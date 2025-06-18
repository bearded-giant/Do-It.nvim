local vim = vim

local Project = {}

function Project.setup(M, config)
    -- Initialize project metadata in the state
    M.project = {
        -- Current project identifier (path or nil)
        current = nil,
        -- Cached project identifiers
        cache = {},
    }

    -- Detect the current project based on Git repository or working directory
    function M.get_project_identifier()
        if not config.options.project or not config.options.project.enabled then
            return nil
        end

        local cwd = vim.fn.getcwd()
        
        -- Check cache first
        if M.project.cache[cwd] then
            return M.project.cache[cwd]
        end
        
        local project_id = nil
        
        -- Try to get git root if enabled
        if config.options.project.detection.use_git then
            local git_root = vim.fn.system('git -C ' .. vim.fn.shellescape(cwd) .. ' rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
            if git_root ~= "" then
                project_id = git_root
            end
        end
        
        -- Fallback to current working directory if enabled and no git root found
        if not project_id and config.options.project.detection.fallback_to_cwd then
            project_id = cwd
        end
        
        -- Cache the result
        M.project.cache[cwd] = project_id
        M.project.current = project_id
        
        return project_id
    end
    
    -- Get the path for storing project-specific todos
    function M.get_project_storage_path()
        local mode = config.options.todo_mode or "global"
        
        -- If not in project mode or project features disabled, return nil
        if mode ~= "project" or not config.options.project or not config.options.project.enabled then
            return nil
        end
        
        local project_id = M.get_project_identifier()
        if not project_id then
            return nil
        end
        
        -- Create a hash of the project path for the filename
        local hash = vim.fn.sha256(project_id)
        local storage_dir = config.options.project.storage.path or (vim.fn.stdpath("data") .. "/doit/projects")
        
        -- Create directory if it doesn't exist
        local mkdir_cmd = vim.fn.has("win32") == 1 and "mkdir" or "mkdir -p"
        vim.fn.system(mkdir_cmd .. " " .. vim.fn.shellescape(storage_dir))
        
        -- Return the path
        return storage_dir .. "/project-" .. string.sub(hash, 1, 10) .. ".json"
    end
    
    -- Get project name for display
    function M.get_project_name()
        local project_id = M.get_project_identifier()
        if not project_id then
            return "Global"
        end
        
        -- Extract the last directory name from the path
        return vim.fn.fnamemodify(project_id, ":t")
    end
    
    -- Reset project cache
    function M.reset_project_cache()
        M.project.cache = {}
        M.project.current = nil
    end
end

return Project