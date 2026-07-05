#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "fs";
import path from "path";

const DATA_DIR = process.env.DOIT_DATA_DIR || path.join(process.env.HOME, ".local/share/nvim/doit");
const LISTS_DIR = path.join(DATA_DIR, "lists");
const SESSION_FILE = path.join(DATA_DIR, "session.json");

const PRIORITY_LABELS = { critical: "!!!", urgent: "!!", important: "!" };

function readJSON(filepath) {
    return JSON.parse(fs.readFileSync(filepath, "utf-8"));
}

function writeJSON(filepath, data) {
    fs.writeFileSync(filepath + ".tmp", JSON.stringify(data, null, 2));
    fs.renameSync(filepath + ".tmp", filepath);
}

function getActiveListName() {
    if (process.env.DOIT_ACTIVE_LIST) return process.env.DOIT_ACTIVE_LIST;
    try {
        const session = readJSON(SESSION_FILE);
        return session.active_list || "daily";
    } catch {
        return "daily";
    }
}

function getListPath(listName) {
    return path.join(LISTS_DIR, `${listName}.json`);
}

function resolveList(listName) {
    return listName || getActiveListName();
}

function loadList(listName) {
    const resolved = resolveList(listName);
    const filepath = getListPath(resolved);
    if (!fs.existsSync(filepath)) {
        throw new Error(`List "${resolved}" not found at ${filepath}`);
    }
    return { name: resolved, filepath, data: readJSON(filepath) };
}

function saveList(filepath, data) {
    data._metadata = data._metadata || {};
    data._metadata.updated_at = Math.floor(Date.now() / 1000);
    writeJSON(filepath, data);
}

function generateId() {
    const ts = Math.floor(Date.now() / 1000);
    const rand = Math.floor(Math.random() * 9999999);
    return `${ts}_${rand}`;
}

function getMaxOrder(todos) {
    if (!todos.length) return 0;
    return Math.max(...todos.map(t => t.order_index || 0));
}

function fuzzyMatch(todos, query) {
    const words = query.toLowerCase().split(/\s+/);
    return todos.filter(t => {
        const hay = t.text.toLowerCase();
        return words.every(w => hay.includes(w));
    });
}

function formatTodoLine(t) {
    const status = t.done ? "[x]" : t.in_progress ? "[~]" : "[ ]";
    const prio = t.priorities ? ` ${PRIORITY_LABELS[t.priorities] || t.priorities}` : "";
    const hasNote = t.description ? " (has notes)" : "";
    return `${status}${prio} ${t.text}${hasNote}  [id:${t.id}]`;
}

function presentChoices(matches, context, actionHint) {
    const lines = matches.map((t, i) => `${i + 1}. ${formatTodoLine(t)}`);
    return {
        content: [{
            type: "text",
            text: `${context}:\n\n${lines.join("\n")}\n\n${actionHint}`,
        }],
    };
}

function formatNoteLine(n) {
    return `${n.title}  [id:${n.id}]`;
}

function presentNoteChoices(matches, context, actionHint) {
    const lines = matches.map((n, i) => `${i + 1}. ${formatNoteLine(n)}`);
    return {
        content: [{
            type: "text",
            text: `${context}:\n\n${lines.join("\n")}\n\n${actionHint}`,
        }],
    };
}

// resolve a list note by id or fuzzy query on title/body
function resolveNote(data, listName, { id, query }) {
    const notes = data.notes || [];

    if (id) {
        const note = notes.find(n => n.id === id);
        if (!note) throw new Error(`Note "${id}" not found in list "${listName}"`);
        return { note };
    }

    if (query) {
        const words = query.toLowerCase().split(/\s+/);
        const matches = notes.filter(n => {
            const hay = `${n.title} ${n.body || ""}`.toLowerCase();
            return words.every(w => hay.includes(w));
        });
        if (matches.length === 0) return { noMatch: `No notes matching "${query}" on "${listName}".` };
        if (matches.length === 1) return { note: matches[0] };
        return { matches };
    }

    return { noMatch: "Provide an id or query to identify the note." };
}

// resolve a todo by id, query, or fallback filter — returns { todo, ambiguous? response }
function resolveTodo(data, listName, { id, query, fallbackFilter }) {
    const todos = data.todos || [];

    if (id) {
        const todo = todos.find(t => t.id === id);
        if (!todo) throw new Error(`Todo "${id}" not found in list "${listName}"`);
        return { todo };
    }

    if (query) {
        const notDone = todos.filter(t => !t.done);
        const matches = fuzzyMatch(notDone, query);
        if (matches.length === 0) return { noMatch: `No pending/in_progress items matching "${query}" on "${listName}".` };
        if (matches.length === 1) return { todo: matches[0] };
        return { matches };
    }

    if (fallbackFilter) {
        const filtered = todos.filter(fallbackFilter);
        if (filtered.length === 0) return { noMatch: null };
        if (filtered.length === 1) return { todo: filtered[0] };
        return { matches: filtered };
    }

    return { noMatch: "Provide an id or query to identify the todo item." };
}

const server = new McpServer(
    {
        name: "doit",
        version: "1.0.0",
    },
    {
        instructions: `Do-it.nvim todo list manager. Data lives at ~/.local/share/nvim/doit/lists/*.json — NOT in any project directory.

IMPORTANT: Always use these MCP tools for todo operations. NEVER use bash, grep, find, cat, or python to read/write todo JSON files directly. The tools handle all data access.

There is always an active list (usually "daily"). When the user says "show my todos", "what's next", "add a todo", or any todo-related request, use these tools directly — no filesystem discovery needed.

Priorities: Items have a 'priorities' field with values: critical, urgent, important, or absent (default/no priority). Priority is a core workflow concept — the user works by priority most days.

Behavior:
- "show todos" / "list todos" / "what's on my list" → list_todos (uses active list automatically)
- "what's next" / "next todo" → list_todos with filter="pending" (first item is next)
- "critical items" / "show urgent" / "what's important" → list_todos with priority filter
- "add todo: ..." / "remind me to ..." → add_todo
- "start the orch todo" / "work on X" → start_todo with query (sets in_progress)
- "complete current todo" / "done with this" → complete_todo (no args — auto-finds in_progress items)
- "complete the orch auth todo" → complete_todo with query="orch auth" (fuzzy text match)
- "revert X to pending" / "un-complete X" → revert_todo with query
- "add note to X" / "note on the orch todo" → add_note with query
- "delete the X todo" → delete_todo with query (fuzzy match, or id)
- "clear done" / "remove completed" → clear_done
- "move X to work list" → move_todo with query + target list
- "search for X" → search_todos
- "show my lists" / "which lists" → list_lists
- "switch to X list" → switch_list
- "todos for <project>" → list_todos with list=<project-name> (list names often match project names)
- "create list X" → create_list
- "rename list X to Y" → rename_list
- "delete list X" → delete_list
- "make a todo from this file" / "take X.md and make a todo" → add_todo with text summarizing the file, and description containing the full file path as a markdown link: [filename](absolute/path/to/file.md). If the file has a title (h1), use that as the todo text. Otherwise use a short summary.
- "add that as a note to X todo" → add_note with the file path or content as the note

List notes: each list also has standalone scratch notes (title + body), parallel to the todo items — NOT attached to any todo. add_note = note ON a todo item; the note tools below manage list-level notes.
- "show notes" / "what notes are on X list" → list_notes (list_todos also shows note titles)
- "read the X note" / "open that note" → get_note with query
- "save this as a note" / "new note: ..." → create_note with title + body
- "add this to the X note" → update_note with mode="append"
- "rewrite the X note" / "rename the note" → update_note (mode="replace" default)
- "delete the X note" → delete_note with query

The list parameter is optional on all tools — omit it to use the active list. Only pass list when the user names a specific list.

All tools that act on a single todo support fuzzy text matching via the 'query' parameter — the user does not need to know the exact todo text or ID.`,
    }
);

// --- READ ---

server.tool(
    "list_todos",
    "List todo items from a do-it list (data at ~/.local/share/nvim/doit/lists/, not in project dir). Returns all items by default, or filter by status and/or priority. Priorities: critical, urgent, important, or none (default). Use this tool instead of reading JSON files directly.",
    {
        list: z.string().optional().describe("List name (default: active list)"),
        filter: z.enum(["all", "pending", "done", "in_progress"]).optional().describe("Filter by status (default: all)"),
        priority: z.enum(["critical", "urgent", "important"]).optional().describe("Filter by priority level. Items without a priority are 'default'."),
    },
    async ({ list, filter = "all", priority }) => {
        const { name, data } = loadList(list);
        let todos = data.todos || [];

        if (filter === "pending") todos = todos.filter(t => !t.done && !t.in_progress);
        else if (filter === "done") todos = todos.filter(t => t.done);
        else if (filter === "in_progress") todos = todos.filter(t => t.in_progress);

        if (priority) {
            todos = todos.filter(t => t.priorities === priority);
        }

        todos.sort((a, b) => (a.order_index || 0) - (b.order_index || 0));

        const lines = todos.map(t => {
            const status = t.done ? "[x]" : t.in_progress ? "[~]" : "[ ]";
            const prio = t.priorities ? ` ${PRIORITY_LABELS[t.priorities] || t.priorities}` : "";
            let line = `${status}${prio} ${t.text}  [id:${t.id}]`;
            if (t.description) {
                const notePreview = t.description.split("\n").map(l => `    ${l}`).join("\n");
                line += `\n    notes:\n${notePreview}`;
            }
            return line;
        });

        const notes = data.notes || [];
        let text = `List: ${name} (${todos.length} items)\n\n${lines.join("\n") || "(empty)"}`;
        if (notes.length) {
            text += `\n\nNotes (${notes.length}):\n${notes.map(n => `- ${formatNoteLine(n)}`).join("\n")}`;
        }

        return {
            content: [{
                type: "text",
                text,
            }],
        };
    }
);

server.tool(
    "search_todos",
    "Search across all do-it todo lists (in ~/.local/share/nvim/doit/lists/) for items matching a text pattern. Use this instead of grepping files.",
    {
        query: z.string().describe("Search text (case-insensitive substring match)"),
        include_done: z.boolean().optional().describe("Include completed items (default: false)"),
    },
    async ({ query, include_done = false }) => {
        const files = fs.readdirSync(LISTS_DIR).filter(f => f.endsWith(".json"));
        const pattern = query.toLowerCase();
        const results = [];

        for (const f of files) {
            const listName = f.replace(/\.json$/, "");
            const data = readJSON(path.join(LISTS_DIR, f));
            for (const t of data.todos || []) {
                if (!include_done && t.done) continue;
                const haystack = `${t.text} ${t.description || ""}`.toLowerCase();
                if (haystack.includes(pattern)) {
                    results.push(`${formatTodoLine(t)}  [list:${listName}]`);
                }
            }
        }

        return {
            content: [{
                type: "text",
                text: results.length
                    ? `Found ${results.length} match(es):\n\n${results.join("\n")}`
                    : `No matches for "${query}"`,
            }],
        };
    }
);

// --- CREATE ---

server.tool(
    "add_todo",
    "Add a new todo item to a do-it list (writes to ~/.local/share/nvim/doit/lists/). Do not write JSON files directly.",
    {
        text: z.string().describe("Todo text"),
        list: z.string().optional().describe("List name (default: active list)"),
        description: z.string().optional().describe("Multi-line notes/description"),
        priority: z.enum(["critical", "urgent", "important"]).optional().describe("Priority level"),
        start: z.boolean().optional().describe("Immediately set as in_progress (default: false)"),
    },
    async ({ text, list, description, priority, start }) => {
        const { name, filepath, data } = loadList(list);
        const id = generateId();
        const newTodo = {
            id,
            text,
            done: false,
            in_progress: start || false,
            order_index: getMaxOrder(data.todos || []) + 1,
            created_at: Math.floor(Date.now() / 1000),
        };
        if (description) newTodo.description = description;
        if (priority) newTodo.priorities = priority;

        data.todos = data.todos || [];
        data.todos.push(newTodo);
        saveList(filepath, data);

        const status = start ? " (in_progress)" : "";
        return {
            content: [{
                type: "text",
                text: `Added to "${name}": ${text}${status} [id:${id}]`,
            }],
        };
    }
);

// --- UPDATE ---

server.tool(
    "update_todo",
    "Update a todo item (in ~/.local/share/nvim/doit/lists/) — change text, description, status (done/in_progress), priority, or reorder. Requires ID. For fuzzy matching, use start_todo/complete_todo/revert_todo instead.",
    {
        id: z.string().describe("Todo ID"),
        list: z.string().optional().describe("List name (default: active list)"),
        text: z.string().optional().describe("New text"),
        description: z.string().optional().describe("New description/notes"),
        priority: z.enum(["critical", "urgent", "important", "none"]).optional().describe("Set priority level. Use 'none' to remove priority."),
        done: z.boolean().optional().describe("Set done status"),
        in_progress: z.boolean().optional().describe("Set in_progress status"),
        order_index: z.number().optional().describe("Set order position"),
    },
    async ({ id, list, text, description, priority, done, in_progress, order_index }) => {
        const { name, filepath, data } = loadList(list);
        const todo = (data.todos || []).find(t => t.id === id);
        if (!todo) throw new Error(`Todo "${id}" not found in list "${name}"`);

        if (text !== undefined) todo.text = text;
        if (description !== undefined) todo.description = description;
        if (priority !== undefined) {
            if (priority === "none") delete todo.priorities;
            else todo.priorities = priority;
        }
        if (done !== undefined) {
            todo.done = done;
            if (done) todo.in_progress = false;
        }
        if (in_progress !== undefined) {
            todo.in_progress = in_progress;
            if (in_progress) todo.done = false;
        }
        if (order_index !== undefined) todo.order_index = order_index;

        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Updated in "${name}": ${todo.text} [done:${todo.done}, in_progress:${todo.in_progress}]`,
            }],
        };
    }
);

server.tool(
    "start_todo",
    "Start a todo item (set in_progress=true). Supports fuzzy text query. Only one item can be in_progress at a time — starting a new one stops the current one.",
    {
        id: z.string().optional().describe("Todo ID."),
        query: z.string().optional().describe("Fuzzy text match (all words must appear)."),
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ id, query, list }) => {
        const { name, filepath, data } = loadList(list);
        const result = resolveTodo(data, name, {
            id, query,
            fallbackFilter: t => !t.done && !t.in_progress,
        });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch || `No pending items on "${name}".` }] };
        }
        if (result.matches) {
            return presentChoices(result.matches, `Multiple items match on "${name}"`, "Ask the user which to start, then call start_todo with the chosen ID.");
        }

        // stop any currently in_progress items
        for (const t of data.todos || []) {
            if (t.in_progress) t.in_progress = false;
        }
        result.todo.in_progress = true;
        result.todo.done = false;
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Started in "${name}": ${result.todo.text}`,
            }],
        };
    }
);

server.tool(
    "complete_todo",
    "Complete a todo item (set done=true). Supports fuzzy text query. With no args, finds in_progress items. Single match auto-completes; multiple returns list for user to pick.",
    {
        id: z.string().optional().describe("Todo ID to complete."),
        query: z.string().optional().describe("Fuzzy text match (all words must appear)."),
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ id, query, list }) => {
        const { name, filepath, data } = loadList(list);
        const result = resolveTodo(data, name, {
            id, query,
            fallbackFilter: t => t.in_progress && !t.done,
        });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch || `No in_progress items on "${name}". Use complete_todo with a query to match by text.` }] };
        }
        if (result.matches) {
            return presentChoices(result.matches, `Multiple items match on "${name}"`, "Ask the user which to complete, then call complete_todo with the chosen ID.");
        }

        result.todo.done = true;
        result.todo.in_progress = false;
        result.todo.completed_at = Math.floor(Date.now() / 1000);
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Completed in "${name}": ${result.todo.text}`,
            }],
        };
    }
);

server.tool(
    "revert_todo",
    "Revert a todo item back to pending (done=false, in_progress=false). Supports fuzzy text query. Useful for un-completing or un-starting items.",
    {
        id: z.string().optional().describe("Todo ID."),
        query: z.string().optional().describe("Fuzzy text match (all words must appear). Searches done and in_progress items."),
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ id, query, list }) => {
        const { name, filepath, data } = loadList(list);
        const result = resolveTodo(data, name, {
            id, query,
            fallbackFilter: t => t.done || t.in_progress,
        });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch || `No done/in_progress items on "${name}" to revert.` }] };
        }
        if (result.matches) {
            return presentChoices(result.matches, `Multiple items match on "${name}"`, "Ask the user which to revert, then call revert_todo with the chosen ID.");
        }

        result.todo.done = false;
        result.todo.in_progress = false;
        delete result.todo.completed_at;
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Reverted to pending in "${name}": ${result.todo.text}`,
            }],
        };
    }
);

server.tool(
    "add_note",
    "Add or update a note (description) on a todo item. Supports fuzzy text query. By default appends to existing notes; use mode='replace' to overwrite.",
    {
        id: z.string().optional().describe("Todo ID."),
        query: z.string().optional().describe("Fuzzy text match (all words must appear)."),
        note: z.string().describe("Note text to add to the todo item."),
        list: z.string().optional().describe("List name (default: active list)"),
        mode: z.enum(["append", "replace"]).optional().describe("'append' (default) adds to existing notes, 'replace' overwrites them."),
    },
    async ({ id, query, note, list, mode = "append" }) => {
        const { name, filepath, data } = loadList(list);
        const result = resolveTodo(data, name, { id, query });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch }] };
        }
        if (result.matches) {
            return presentChoices(result.matches, `Multiple items match on "${name}"`, "Ask the user which item to add the note to, then call add_note with the chosen ID.");
        }

        const todo = result.todo;
        if (mode === "replace" || !todo.description) {
            todo.description = note;
        } else {
            todo.description = todo.description.trimEnd() + "\n\n" + note;
        }
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Note ${mode === "replace" ? "set" : "added"} on "${name}": ${todo.text}\n\nFull note:\n${todo.description}`,
            }],
        };
    }
);

// --- DELETE ---

server.tool(
    "delete_todo",
    "Delete a todo item. Supports fuzzy text query. Moves to _metadata.deleted_todos for undo support.",
    {
        id: z.string().optional().describe("Todo ID."),
        query: z.string().optional().describe("Fuzzy text match (all words must appear)."),
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ id, query, list }) => {
        const { name, filepath, data } = loadList(list);
        const result = resolveTodo(data, name, { id, query });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch }] };
        }
        if (result.matches) {
            return presentChoices(result.matches, `Multiple items match on "${name}"`, "Ask the user which to delete, then call delete_todo with the chosen ID.");
        }

        const idx = data.todos.findIndex(t => t.id === result.todo.id);
        const [removed] = data.todos.splice(idx, 1);
        data._metadata = data._metadata || {};
        data._metadata.deleted_todos = data._metadata.deleted_todos || [];
        data._metadata.deleted_todos.unshift(removed);
        data._metadata.deleted_todos = data._metadata.deleted_todos.slice(0, 10);

        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Deleted from "${name}": ${removed.text}`,
            }],
        };
    }
);

server.tool(
    "clear_done",
    "Delete all completed (done) items from a list. Moves them to _metadata.deleted_todos (last 10 kept for undo).",
    {
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ list }) => {
        const { name, filepath, data } = loadList(list);
        const done = (data.todos || []).filter(t => t.done);

        if (done.length === 0) {
            return { content: [{ type: "text", text: `No completed items on "${name}".` }] };
        }

        data.todos = data.todos.filter(t => !t.done);
        data._metadata = data._metadata || {};
        data._metadata.deleted_todos = [...done, ...(data._metadata.deleted_todos || [])].slice(0, 10);
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Cleared ${done.length} completed items from "${name}".`,
            }],
        };
    }
);

// --- LIST NOTES (list-scoped scratch notes, parallel to todos — not todo descriptions) ---

server.tool(
    "list_notes",
    "List the list-scoped scratch notes on a do-it list (top-level notes array, separate from todo item descriptions). Returns titles + ids; use get_note for a full body.",
    {
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ list }) => {
        const { name, data } = loadList(list);
        const notes = data.notes || [];
        const lines = notes.map(n => `- ${formatNoteLine(n)}`);

        return {
            content: [{
                type: "text",
                text: `Notes on "${name}" (${notes.length}):\n\n${lines.join("\n") || "(none)"}`,
            }],
        };
    }
);

server.tool(
    "get_note",
    "Read the full body of one list note. Find by id or fuzzy query on title/body.",
    {
        id: z.string().optional().describe("Note ID."),
        query: z.string().optional().describe("Fuzzy text match on title/body (all words must appear)."),
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ id, query, list }) => {
        const { name, data } = loadList(list);
        const result = resolveNote(data, name, { id, query });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch }] };
        }
        if (result.matches) {
            return presentNoteChoices(result.matches, `Multiple notes match on "${name}"`, "Ask the user which note, then call get_note with the chosen ID.");
        }

        const n = result.note;
        return {
            content: [{
                type: "text",
                text: `# ${n.title}  [id:${n.id}]\n\n${n.body || "(empty body)"}`,
            }],
        };
    }
);

server.tool(
    "create_note",
    "Create a new list-scoped scratch note on a do-it list (standalone, not attached to any todo — to note on a todo item use add_note).",
    {
        title: z.string().describe("Note title (single line, shown in list rows)"),
        body: z.string().optional().describe("Note body (may contain newlines)"),
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ title, body, list }) => {
        const { name, filepath, data } = loadList(list);
        const now = Math.floor(Date.now() / 1000);
        const note = {
            id: generateId(),
            title,
            body: body || "",
            created_at: now,
            updated_at: now,
        };
        data.notes = data.notes || [];
        data.notes.push(note);
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Created note on "${name}": ${formatNoteLine(note)}`,
            }],
        };
    }
);

server.tool(
    "update_note",
    "Update a list note's title and/or body. Find by id or fuzzy query. Body mode: 'replace' (default) overwrites, 'append' adds to existing body.",
    {
        id: z.string().optional().describe("Note ID."),
        query: z.string().optional().describe("Fuzzy text match on title/body (all words must appear)."),
        list: z.string().optional().describe("List name (default: active list)"),
        title: z.string().optional().describe("New title"),
        body: z.string().optional().describe("New/additional body text"),
        mode: z.enum(["replace", "append"]).optional().describe("'replace' (default) overwrites body, 'append' adds to it"),
    },
    async ({ id, query, list, title, body, mode = "replace" }) => {
        const { name, filepath, data } = loadList(list);
        const result = resolveNote(data, name, { id, query });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch }] };
        }
        if (result.matches) {
            return presentNoteChoices(result.matches, `Multiple notes match on "${name}"`, "Ask the user which note to update, then call update_note with the chosen ID.");
        }

        const note = result.note;
        if (title !== undefined) note.title = title;
        if (body !== undefined) {
            if (mode === "append" && note.body) {
                note.body = note.body.trimEnd() + "\n\n" + body;
            } else {
                note.body = body;
            }
        }
        note.updated_at = Math.floor(Date.now() / 1000);
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Updated note on "${name}": ${formatNoteLine(note)}`,
            }],
        };
    }
);

server.tool(
    "delete_note",
    "Delete a list note. Find by id or fuzzy query. Moves to _metadata.deleted_notes (last 10 kept).",
    {
        id: z.string().optional().describe("Note ID."),
        query: z.string().optional().describe("Fuzzy text match on title/body (all words must appear)."),
        list: z.string().optional().describe("List name (default: active list)"),
    },
    async ({ id, query, list }) => {
        const { name, filepath, data } = loadList(list);
        const result = resolveNote(data, name, { id, query });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch }] };
        }
        if (result.matches) {
            return presentNoteChoices(result.matches, `Multiple notes match on "${name}"`, "Ask the user which note to delete, then call delete_note with the chosen ID.");
        }

        const idx = data.notes.findIndex(n => n.id === result.note.id);
        const [removed] = data.notes.splice(idx, 1);
        data._metadata = data._metadata || {};
        data._metadata.deleted_notes = data._metadata.deleted_notes || [];
        data._metadata.deleted_notes.unshift(removed);
        data._metadata.deleted_notes = data._metadata.deleted_notes.slice(0, 10);
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Deleted note from "${name}": ${removed.title}`,
            }],
        };
    }
);

// --- MOVE ---

server.tool(
    "move_todo",
    "Move a todo item from one list to another. Supports fuzzy text query to find the item.",
    {
        id: z.string().optional().describe("Todo ID."),
        query: z.string().optional().describe("Fuzzy text match (all words must appear)."),
        from_list: z.string().optional().describe("Source list (default: active list)"),
        to_list: z.string().describe("Target list name to move the item to"),
    },
    async ({ id, query, from_list, to_list }) => {
        const source = loadList(from_list);
        const result = resolveTodo(source.data, source.name, { id, query });

        if (result.noMatch) {
            return { content: [{ type: "text", text: result.noMatch }] };
        }
        if (result.matches) {
            return presentChoices(result.matches, `Multiple items match on "${source.name}"`, "Ask the user which to move, then call move_todo with the chosen ID.");
        }

        const targetPath = getListPath(to_list);
        if (!fs.existsSync(targetPath)) {
            throw new Error(`Target list "${to_list}" not found. Use list_lists to see available lists.`);
        }
        const targetData = readJSON(targetPath);

        // remove from source
        const idx = source.data.todos.findIndex(t => t.id === result.todo.id);
        const [moved] = source.data.todos.splice(idx, 1);

        // add to target
        moved.order_index = getMaxOrder(targetData.todos || []) + 1;
        targetData.todos = targetData.todos || [];
        targetData.todos.push(moved);

        saveList(source.filepath, source.data);
        saveList(targetPath, targetData);

        return {
            content: [{
                type: "text",
                text: `Moved from "${source.name}" to "${to_list}": ${moved.text}`,
            }],
        };
    }
);

// --- LIST MANAGEMENT ---

server.tool(
    "list_lists",
    "Show all available do-it todo lists (from ~/.local/share/nvim/doit/lists/) and which one is active.",
    {},
    async () => {
        const files = fs.readdirSync(LISTS_DIR).filter(f => f.endsWith(".json"));
        const active = getActiveListName();

        const lines = files.map(f => {
            const name = f.replace(/\.json$/, "");
            const data = readJSON(path.join(LISTS_DIR, f));
            const total = (data.todos || []).length;
            const pending = (data.todos || []).filter(t => !t.done).length;
            const marker = name === active ? " <-- active" : "";
            return `${name}: ${pending} pending / ${total} total${marker}`;
        });

        return {
            content: [{
                type: "text",
                text: lines.join("\n"),
            }],
        };
    }
);

server.tool(
    "switch_list",
    "Switch the active do-it list.",
    {
        list: z.string().describe("List name to switch to"),
    },
    async ({ list }) => {
        const filepath = getListPath(list);
        if (!fs.existsSync(filepath)) {
            throw new Error(`List "${list}" not found. Use list_lists to see available lists.`);
        }

        const session = fs.existsSync(SESSION_FILE) ? readJSON(SESSION_FILE) : {};
        session.active_list = list;
        session.timestamp = Math.floor(Date.now() / 1000);
        writeJSON(SESSION_FILE, session);

        return {
            content: [{
                type: "text",
                text: `Switched active list to "${list}"`,
            }],
        };
    }
);

server.tool(
    "create_list",
    "Create a new empty do-it todo list.",
    {
        name: z.string().describe("List name (used as filename, no spaces — use hyphens)"),
    },
    async ({ name }) => {
        const filepath = getListPath(name);
        if (fs.existsSync(filepath)) {
            throw new Error(`List "${name}" already exists.`);
        }

        const data = {
            todos: [],
            _metadata: {
                created_at: Math.floor(Date.now() / 1000),
                updated_at: Math.floor(Date.now() / 1000),
            },
        };
        writeJSON(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Created list "${name}" at ${filepath}`,
            }],
        };
    }
);

server.tool(
    "rename_list",
    "Rename a do-it todo list. Cannot rename the active list (switch away first).",
    {
        old_name: z.string().describe("Current list name"),
        new_name: z.string().describe("New list name (no spaces — use hyphens)"),
    },
    async ({ old_name, new_name }) => {
        const oldPath = getListPath(old_name);
        const newPath = getListPath(new_name);

        if (!fs.existsSync(oldPath)) {
            throw new Error(`List "${old_name}" not found.`);
        }
        if (fs.existsSync(newPath)) {
            throw new Error(`List "${new_name}" already exists.`);
        }
        if (old_name === getActiveListName()) {
            throw new Error(`Cannot rename the active list "${old_name}". Switch to another list first.`);
        }

        fs.renameSync(oldPath, newPath);

        return {
            content: [{
                type: "text",
                text: `Renamed list "${old_name}" to "${new_name}"`,
            }],
        };
    }
);

server.tool(
    "delete_list",
    "Delete an entire do-it todo list. Cannot delete the active list.",
    {
        name: z.string().describe("List name to delete"),
    },
    async ({ name }) => {
        const filepath = getListPath(name);
        if (!fs.existsSync(filepath)) {
            throw new Error(`List "${name}" not found.`);
        }
        if (name === getActiveListName()) {
            throw new Error(`Cannot delete the active list "${name}". Switch to another list first.`);
        }

        const data = readJSON(filepath);
        const count = (data.todos || []).length;
        fs.unlinkSync(filepath);

        return {
            content: [{
                type: "text",
                text: `Deleted list "${name}" (had ${count} items)`,
            }],
        };
    }
);

const transport = new StdioServerTransport();
await server.connect(transport);
