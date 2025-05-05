-- Theme and highlighting utilities for doit.nvim
local M = {}

-- Set up highlight groups
function M.setup()
    -- Base highlight groups
    vim.cmd [[
        highlight default DoitPending guifg=#7eae81 ctermfg=green
        highlight default DoitInProgress guifg=#f5d547 ctermfg=yellow
        highlight default DoitDone guifg=#61afef ctermfg=blue gui=strikethrough cterm=strikethrough
        highlight default DoitHelpText guifg=#abb2bf ctermfg=white
        highlight default DoitQuickTitle guifg=#e5c07b ctermfg=yellow
        highlight default DoitQuickKey guifg=#e06c75 ctermfg=red
        highlight default DoitQuickDesc guifg=#abb2bf ctermfg=white
    ]]
    
    -- Priority highlight groups
    vim.cmd [[
        highlight default DoitPriorityCritical guifg=#e06c75 ctermfg=red
        highlight default DoitPriorityHigh guifg=#e5c07b ctermfg=yellow
        highlight default DoitPriorityMedium guifg=#61afef ctermfg=blue
        highlight default DoitPriorityLow guifg=#abb2bf ctermfg=white
    ]]
    
    -- Tag highlight group
    vim.cmd [[
        highlight default DoitTag guifg=#c678dd ctermfg=magenta
    ]]
    
    -- Date highlight group
    vim.cmd [[
        highlight default DoitDate guifg=#56b6c2 ctermfg=cyan
    ]]
    
    -- Time highlight group
    vim.cmd [[
        highlight default DoitTime guifg=#98c379 ctermfg=green
    ]]
    
    -- Create links to diagnostic highlight groups if they exist
    if vim.fn.hlexists("DiagnosticError") == 1 then
        vim.cmd [[highlight link DoitPriorityCritical DiagnosticError]]
    end
    
    if vim.fn.hlexists("DiagnosticWarn") == 1 then
        vim.cmd [[highlight link DoitPriorityHigh DiagnosticWarn]]
    end
    
    if vim.fn.hlexists("DiagnosticInfo") == 1 then
        vim.cmd [[highlight link DoitPriorityMedium DiagnosticInfo]]
    end
    
    if vim.fn.hlexists("DiagnosticHint") == 1 then
        vim.cmd [[highlight link DoitPriorityLow DiagnosticHint]]
    end
    
    -- Create links to existing syntax highlighting groups for notes
    vim.cmd [[
        highlight default link DoItNotesHeading Title
        highlight default link DoItNotesLink Underlined
        highlight default link DoItNotesBold Statement
        highlight default link DoItNotesItalic Comment
    ]]
end

-- Get highlight color
function M.get_highlight_color(name, attr)
    attr = attr or "fg"
    local ok, hl = pcall(vim.api.nvim_get_hl_by_name, name, true)
    if ok and hl and hl[attr] then
        return string.format("#%06x", hl[attr])
    end
    return nil
end

-- Create custom highlight group
function M.create_highlight(name, fg, bg, gui)
    local cmd = "highlight default " .. name
    
    if fg then
        cmd = cmd .. " guifg=" .. fg
    end
    
    if bg then
        cmd = cmd .. " guibg=" .. bg
    end
    
    if gui then
        cmd = cmd .. " gui=" .. gui
    end
    
    vim.cmd(cmd)
end

-- Link highlight groups
function M.link_highlight(from, to)
    vim.cmd("highlight default link " .. from .. " " .. to)
end

-- Apply priority color based on group
function M.get_priority_color(priority_group)
    if priority_group == "critical" then
        return M.get_highlight_color("DoitPriorityCritical")
    elseif priority_group == "high" then
        return M.get_highlight_color("DoitPriorityHigh")
    elseif priority_group == "medium" then
        return M.get_highlight_color("DoitPriorityMedium")
    else
        return M.get_highlight_color("DoitPriorityLow")
    end
end

return M
