# Codebase Concerns

**Analysis Date:** 2026-01-19

## Tech Debt

**Duplicated State Management Pattern:**
- Issue: `ensure_state_loaded()` and `get_todo_module()` functions are duplicated across 5 files with slight variations
- Files:
  - `lua/doit/ui/main_window.lua` (lines 21-84)
  - `lua/doit/ui/todo_actions.lua` (lines 7-50)
  - `lua/doit/ui/list_window.lua`
  - `lua/doit/ui/category_window.lua`
  - `lua/doit/lualine.lua`
- Impact: Inconsistent state initialization, risk of divergent behavior, maintenance burden
- Fix approach: Extract to a shared `lua/doit/core/utils/state.lua` module and import in all files

**Large Monolithic Files:**
- Issue: Several UI files exceed 500 lines with mixed concerns
- Files:
  - `lua/doit/ui/todo_actions.lua` (1319 lines) - reordering, priority selection, time estimation, due dates all in one file
  - `lua/doit/ui/main_window.lua` (1143 lines) - window creation, rendering, keymaps, linked note handling
  - `lua/doit/modules/obsidian-sync/init.lua` (797 lines) - setup, hooks, commands, sync logic
  - `lua/doit/modules/todos/ui/list_manager_window.lua` (660 lines)
  - `lua/doit/modules/todos/state/storage.lua` (656 lines)
- Impact: Difficult to test in isolation, hard to navigate, prone to merge conflicts
- Fix approach: Split into focused sub-modules (e.g., `todo_actions/reordering.lua`, `todo_actions/priority.lua`)

**Fallback Empty State Pattern:**
- Issue: Multiple files create empty stub state objects as "last resort" fallback
- Files:
  - `lua/doit/ui/main_window.lua` (lines 56-76)
  - `lua/doit/ui/todo_actions.lua` (lines 36-49)
- Impact: Silent failures, potentially invalid state, hard to debug issues
- Fix approach: Fail fast with clear error messages when state unavailable

**Deprecated API Usage:**
- Issue: File uses deprecated Neovim APIs
- Files: `lua/doit/ui/init.lua` (line 1: `---@diagnostic disable: undefined-global, param-type-mismatch, deprecated`)
- Impact: Future Neovim versions may break functionality
- Fix approach: Audit and update to modern API equivalents

**Shell Command Dependency:**
- Issue: Uses shell commands for file operations instead of pure Lua
- Files:
  - `lua/doit/modules/todos/state/storage.lua` (line 56: `vim.fn.system(mkdir_cmd...)`)
  - `lua/doit/modules/todos/state/storage.lua` (lines 79-80: `ls` command for file listing)
- Impact: Platform inconsistency (Windows vs Unix), security concerns with shell escaping
- Fix approach: Use `vim.fn.mkdir()` and `vim.fn.glob()` or `vim.loop` (libuv) for portability

**Hardcoded Vault Path:**
- Issue: Obsidian vault path pattern hardcoded in autocmd
- Files: `lua/doit/modules/obsidian-sync/init.lua` (lines 634, 646: `**/Recharge-Notes/**/*.md`)
- Impact: Users with different vault names cannot use auto-import feature
- Fix approach: Use `M.config.vault_path` pattern in autocmd instead of hardcoded string

## Known Bugs

**Keymap Duplication:**
- Symptoms: `import_todos` and `export_todos` keymaps are set twice
- Files: `lua/doit/ui/main_window.lua` (lines 952-970)
- Trigger: Opening todo window sets duplicate keymaps
- Workaround: Second setup overwrites first, no user-visible issue

**Cursor Position Off-by-One Potential:**
- Symptoms: Cursor may land on wrong todo line when multiline todos present
- Files:
  - `lua/doit/ui/todo_actions.lua` (function `get_real_todo_index`)
  - `lua/doit/ui/main_window.lua` (function `calculate_line_offset`)
- Trigger: Filtering by tag or category with multiline todos
- Workaround: Navigate manually after filter operations

## Security Considerations

**File Path Injection Risk:**
- Risk: User-provided paths passed to shell commands without sufficient validation
- Files:
  - `lua/doit/modules/todos/state/storage.lua` (line 56: `vim.fn.shellescape` used but path concatenated first)
  - Import/export functions accept arbitrary file paths
- Current mitigation: `vim.fn.shellescape()` used in some places
- Recommendations: Validate paths are within expected directories, use Lua `io` operations instead of shell

**JSON Decode Without Validation:**
- Risk: Malformed JSON files could cause errors or unexpected behavior
- Files:
  - `lua/doit/modules/todos/state/storage.lua` (multiple `pcall(vim.fn.json_decode...)` calls)
  - `lua/doit/modules/todos/state/session.lua`
- Current mitigation: `pcall` wraps decode
- Recommendations: Add schema validation for imported data structure

## Performance Bottlenecks

**Full List Traversal for Search:**
- Problem: Finding todo by ID requires iterating all lists
- Files: `lua/doit/modules/obsidian-sync/init.lua` (function `find_todo_by_id`, lines 87-165)
- Cause: No index or map for todo IDs; must load/unload lists to search
- Improvement path: Maintain a global `todo_id -> list_name` index

**Sync on Every Buffer Enter:**
- Problem: `refresh_buffer_refs` runs on every BufEnter for Obsidian files
- Files: `lua/doit/modules/obsidian-sync/init.lua` (lines 645-651)
- Cause: Autocmd pattern matches all markdown files in vault
- Improvement path: Debounce or only sync when file content changed

**Sorting on Every Render:**
- Problem: `state.sort_todos()` called on every render
- Files: `lua/doit/ui/main_window.lua` (line 234)
- Cause: Sort runs even when no changes occurred
- Improvement path: Track dirty flag, only sort when todos modified

## Fragile Areas

**Obsidian Sync Hook Patching:**
- Files: `lua/doit/modules/obsidian-sync/init.lua` (lines 703-777)
- Why fragile: Monkey-patches `todo_actions.toggle_todo` at runtime after 500ms delay
- Safe modification: Must preserve original function behavior exactly
- Test coverage: Limited - only integration tests exist

**Line Number Calculation:**
- Files:
  - `lua/doit/ui/todo_actions.lua` (functions `get_real_todo_index`, `find_bullet_line_for_cursor`)
  - `lua/doit/ui/main_window.lua` (function `calculate_line_offset`)
- Why fragile: Offset calculations depend on filter state, multiline todos, header lines
- Safe modification: Must update all three calculation sites together
- Test coverage: Some coverage in `reordering_spec.lua`, gaps for multiline scenarios

**Module Loading Order:**
- Files: `lua/doit/init.lua` (setup function, lines 5-80)
- Why fragile: Complex initialization with legacy compatibility, fallback loading, multiple paths
- Safe modification: Test all initialization scenarios (fresh setup, partial config, migration)
- Test coverage: Minimal

## Scaling Limits

**Single JSON File Per List:**
- Current capacity: Works fine for hundreds of todos
- Limit: Performance degrades with thousands of todos (full file read/write on every change)
- Scaling path: Consider SQLite or incremental JSON patches

**In-Memory State:**
- Current capacity: All todos loaded into memory
- Limit: Memory issues with very large datasets
- Scaling path: Lazy loading, pagination for display

## Dependencies at Risk

**icalbuddy (macOS only):**
- Risk: Calendar module requires macOS-specific tool
- Impact: Calendar features unavailable on Linux/Windows
- Migration plan: Docker generates mock events; consider native ICS parsing

**obsidian.nvim (optional):**
- Risk: Tight coupling with obsidian.nvim plugin internals
- Impact: obsidian.nvim updates could break sync
- Migration plan: Fallback to manual [[link]] syntax works without obsidian.nvim

## Missing Critical Features

**No Undo for Edits:**
- Problem: Todo text edits cannot be undone (only delete has undo)
- Blocks: Users may accidentally lose edited content

**No Concurrent Access Handling:**
- Problem: Multiple Neovim instances editing same list can corrupt data
- Blocks: Safe multi-instance workflows

## Test Coverage Gaps

**UI Components:**
- What's not tested: Most window creation, keymap setup, cursor movement
- Files: `lua/doit/ui/*.lua` (only `todo_actions_spec.lua` exists)
- Risk: UI regressions undetected
- Priority: Medium

**Module Loading:**
- What's not tested: Various initialization paths in `lua/doit/init.lua`
- Files: `lua/doit/init.lua`
- Risk: Startup failures in edge cases
- Priority: High

**Calendar Module:**
- What's not tested: icalbuddy parsing edge cases, date formatting in different locales
- Files: `lua/doit/modules/calendar/icalbuddy.lua`
- Risk: Parser failures on unusual event formats
- Priority: Low (commented-out debug code suggests active debugging)

**Storage Migration:**
- What's not tested: Migration from old format, cross-list operations
- Files: `lua/doit/modules/todos/state/storage.lua` (lines 211-249)
- Risk: Data loss during migration scenarios
- Priority: High

**Test File to Source Ratio:**
- 20 test files for 87 source files (23% coverage by file count)
- Notable gaps: `core/ui/`, `modules/notes/state/`, most `ui/` files

---

*Concerns audit: 2026-01-19*
