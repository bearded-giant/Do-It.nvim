# Do-It.nvim Project Status - January 2025

## Overview

The project has been changed to more of a modular framework (v2.0.0) that supports plugin-like modules. The framework is operational with two main modules to start with: Todos and Notes.

## Current Branch: `new-framework`

## What's Working

### 1. Core Framework (v2.0.0)

- ✅ Module registry system for dynamic module loading
- ✅ Event system for inter-module communication
- ✅ Configuration management
- ✅ UI framework utilities
- ✅ Auto-discovery of modules
- ✅ Backward compatibility with legacy API

### 2. Dashboard

- ✅ Framework dashboard showing version, loaded modules, and commands
- ✅ Accessible via `:DoItDashboard` or `require('doit').show_dashboard()`

### 3. Todos Module (v2.0.0)

- ✅ Multiple todo lists support
- ✅ Priority system (high, medium, low)
- ✅ Due dates
- ✅ Tags and categories
- ✅ Search functionality
- ✅ Import/export capabilities
- ✅ Note linking with `[[note-title]]` syntax
- ✅ Complete UI with keybindings
- ✅ State persistence

### 4. Notes Module (v1.0.0)

- ✅ Project-specific and global notes
- ✅ Markdown support with syntax highlighting
- ✅ Note storage management
- ✅ Integration with todos via events
- ✅ Basic keybindings and UI

### 5. Plugin Management

- ✅ `:DoItPlugins` command with subcommands:
  - `list` - List available plugins
  - `info <module>` - Show module information
  - `install <source>` - Install a module
  - `uninstall <module>` - Remove a module
  - `update <module>` - Update a module
  - `enable/disable <module>` - Toggle module state

## Commands Available

```
:DoIt              - Toggle main todo window
:DoItList          - Toggle quick todo list
:DoItLists         - Manage todo lists
:DoItNotes         - Toggle notes window
:DoItDashboard     - Show framework dashboard
:DoItPlugins       - Manage plugins
```

## Test Status

All tests are passing:

- Framework tests: 5/5 ✅
- Core tests: 4/4 ✅
- Todos module tests: 3/3 ✅
- Notes module tests: 3/3 ✅
- State management tests: 35/35 ✅
- UI tests: 25/25 ✅
- Linking tests: 18/18 ✅

## Architecture Changes

The project evolved from the original plan:

1. Instead of integrating key features directly, created a modular framework
2. Todos and Notes are now separate modules that communicate via events
3. Framework supports dynamic module loading and management
4. Legacy API maintained for backward compatibility

## What's Left to Do

### Core Framework

- [ ] Documentation for module developers
- [ ] Module template/generator
- [ ] Module marketplace/registry integration
- [ ] Enhanced module dependency management

### Dashboard Improvements

- [ ] Module statistics
- [ ] Recent activity display
- [ ] Quick actions panel
- [ ] Customizable dashboard layout

### Additional Modules

- [ ] Calendar module for date-based views
- [ ] Project management module
- [ ] Time tracking module
- [ ] Habit tracker module

### General Improvements

- [ ] Performance optimizations for large datasets
- [ ] Enhanced search across all modules
- [ ] Unified command palette
- [ ] Module theming support

## Quick Start for Testing

1. Install the plugin
2. Run `:DoItDashboard` to see the framework status
3. Use `:DoIt` to open todos
4. Use `:DoItNotes` to open notes
5. Try linking todos to notes with `[[note-title]]` syntax
6. Run tests with: `docker/run-tests.sh`

## Module Development

New modules can be created in `lua/doit/modules/<module-name>/` with:

- `init.lua` - Module definition with metadata
- `state/` - State management
- `ui/` - UI components
- `config.lua` - Module configuration

The framework will auto-discover and load modules on startup.

