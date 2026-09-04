#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "fs";
import path from "path";
import { execFileSync } from "child_process";
import { fileURLToPath } from "url";
import { composeTodoText, nextRank, normalizeTodoText, parseTodoText } from "./todo-text.js";

// Root VERSION is the single source of truth, read at runtime exactly as the
// nvim (init.lua read_version) and tmux (DOIT_VERSION) surfaces do, so a release
// bump does not have to be repeated here.
function readVersion() {
    try {
        const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
        return fs.readFileSync(path.join(root, "VERSION"), "utf-8").trim() || "0.0.0";
    } catch {
        return "0.0.0";
    }
}

const DATA_DIR = process.env.DOIT_DATA_DIR || path.join(process.env.HOME, ".local/share/nvim/doit");
const LISTS_DIR = path.join(DATA_DIR, "lists");
const SESSION_FILE = path.join(DATA_DIR, "session.json");

const PRIORITY_LABELS = { critical: "!!!", urgent: "!!", important: "!" };

// nudge callers to write human-readable notes — these render in the tmux/nvim
// right pane, so dense single-block walls are unreadable. claude:-prefixed
// todos are LLM burn-down items (machine-read) and don't need this.
const TYPE_HINT =
    " Short lowercase tag for the kind of work, rendered as a scannable [tag]" +
    " prefix — e.g. decision, gate, loader, comms, bug, spike, chore, research." +
    " Free-form: coin a new one when none fit. Always set it on MCP-created items.";

const DEPS_HINT =
    " Rank numbers this item depends on, e.g. [12, 28] renders '(dep on #12, #28)'." +
    " Reference the leading N. of the blocking item, not its id. Pass [] to clear.";

const NOTE_FORMAT_HINT =
    " Format for a human reader: each labeled section on its own line, a blank" +
    " line between sections, commands/paths/code on their own lines (fence" +
    " multi-line code with ```). Don't cram it into one dense paragraph." +
    " (Exception: todos whose text starts 'claude:' are machine-read — plain is fine.)";

function readJSON(filepath) {
    return JSON.parse(fs.readFileSync(filepath, "utf-8"));
}

function writeJSON(filepath, data) {
    fs.writeFileSync(filepath + ".tmp", JSON.stringify(data, null, 2));
    fs.renameSync(filepath + ".tmp", filepath);
}

// Current tmux session name, or null outside tmux. Resolved per call, not per
// process — the user moves panes between sessions and the server lives long.
function getTmuxSessionName() {
    if (!process.env.TMUX) return null;
    try {
        const target = process.env.TMUX_PANE ? ["-t", process.env.TMUX_PANE] : [];
        const out = execFileSync("tmux", ["display-message", "-p", ...target, "#S"], {
            encoding: "utf-8",
            stdio: ["ignore", "pipe", "ignore"],
        });
        return out.trim() || null;
    } catch {
        return null;
    }
}

function readSession() {
    try {
        return readJSON(SESSION_FILE);
    } catch {
        return {};
    }
}

function updateSession(mutate) {
    const session = readSession();
    mutate(session);
    session.timestamp = Math.floor(Date.now() / 1000);
    writeJSON(SESSION_FILE, session);
}

// env override > per-tmux-session link > global .active_list > daily
function getActiveListName() {
    if (process.env.DOIT_ACTIVE_LIST) return process.env.DOIT_ACTIVE_LIST;
    const session = readSession();
    const sess = getTmuxSessionName();
    const link = sess && session.sessions ? session.sessions[sess] : null;
    if (link && fs.existsSync(getListPath(link))) return link;
    return session.active_list || "daily";
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

// Tags live inline in the todo text, not in a schema field — same contract as
// the nvim and tmux surfaces. Matching is exact-token, so #labels never matches
// #labels-web. Charset mirrors state/tags.lua's [%w_%-/]+.
const TAG_PATTERN = /#([\w\-/]+)/g;

function parseTags(text) {
    return [...String(text || "").matchAll(TAG_PATTERN)].map(m => m[1]);
}

function hasTag(text, tag) {
    if (!tag) return true;
    return parseTags(text).includes(tag);
}

// Due dates are "YYYY-MM-DD" strings in the shared `due_date` field, matching
// state/due_dates.lua. Both ends of the comparison are taken at noon so a DST
// shift cannot round the difference to the wrong day.
const DUE_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function parseDue(due) {
    if (typeof due !== "string" || !DUE_DATE_RE.test(due)) return null;
    const [y, m, d] = due.split("-").map(Number);
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    const dt = new Date(y, m - 1, d, 12);
    if (dt.getFullYear() !== y || dt.getMonth() !== m - 1 || dt.getDate() !== d) return null;
    return dt;
}

function daysUntilDue(due, now) {
    const dt = parseDue(due);
    if (!dt) return null;
    const ref = now || new Date();
    const todayNoon = new Date(ref.getFullYear(), ref.getMonth(), ref.getDate(), 12);
    return Math.round((dt - todayNoon) / 86400000);
}

function renderDue(due, now) {
    const days = daysUntilDue(due, now);
    if (days === null) return "";
    if (days < 0) return `overdue ${-days}d`;
    if (days === 0) return "due today";
    if (days === 1) return "due tomorrow";
    return `in ${days}d`;
}

// Nesting: parent_id + depth, mirroring state/sorting.lua's structure_aware().
// A child rides with its parent so a subtree is contiguous and never splits
// across a section, and a child whose parent is missing is treated as a root so
// nothing disappears from the listing.
function structureAware(todos) {
    const byId = new Map(todos.map(t => [t.id, t]));
    const children = new Map();
    const roots = [];

    for (const todo of todos) {
        const parent = todo.parent_id ? byId.get(todo.parent_id) : null;
        if (parent && parent !== todo) {
            if (!children.has(todo.parent_id)) children.set(todo.parent_id, []);
            children.get(todo.parent_id).push(todo);
        } else {
            roots.push(todo);
        }
    }

    const byOrder = (a, b) => (a.order_index || 0) - (b.order_index || 0);
    roots.sort(byOrder);
    for (const group of children.values()) group.sort(byOrder);

    const ordered = [];
    const seen = new Set();
    const emit = (todo, depth) => {
        if (seen.has(todo.id)) return;
        seen.add(todo.id);
        ordered.push({ todo, depth });
        for (const child of children.get(todo.id) || []) emit(child, depth + 1);
    };
    for (const root of roots) emit(root, 0);
    // anything left sat in a parent cycle; keep it reachable
    for (const todo of todos) if (!seen.has(todo.id)) ordered.push({ todo, depth: 0 });

    return ordered;
}

// Accepts an id or a rank number (the leading "N." the user scans), matching how
// deps are referenced.
function resolveTodoRef(todos, ref) {
    if (ref === undefined || ref === null || ref === "") return null;
    const asId = todos.find(t => t.id === String(ref));
    if (asId) return asId;
    const rank = Number(String(ref).replace(/^#/, ""));
    if (!Number.isNaN(rank)) {
        const byRank = todos.find(t => parseTodoText(t.text).rank === rank);
        if (byRank) return byRank;
    }
    return undefined; // explicitly "asked for one, found none"
}

function descendantIds(todos, rootId) {
    const out = new Set();
    const walk = id => {
        for (const t of todos) {
            if (t.parent_id === id && !out.has(t.id)) {
                out.add(t.id);
                walk(t.id);
            }
        }
    };
    walk(rootId);
    return out;
}

function redepth(todos, parentId, depth) {
    for (const t of todos) {
        if (t.parent_id === parentId) {
            t.depth = depth;
            redepth(todos, t.id, depth + 1);
        }
    }
}

// Promote a deleted todo's DIRECT children to top level. Their own descendants
// stay attached and are only re-depthed — a grandchild must not be orphaned
// because its grandparent went away. Completion is per-item with no cascade, so
// a child never vanishes because its parent was deleted.
function promoteChildren(todos, parentId) {
    for (const t of todos) {
        if (t.parent_id === parentId) {
            delete t.parent_id;
            t.depth = 0;
            redepth(todos, t.id, 1);
        }
    }
}

// Drop the machine-managed footer so re-saving refreshes the stamp instead of
// stacking. Matches either verb so older "last updated" stamps are stripped too.
function stripFooter(desc) {
    return (desc || "").replace(/\n*----------\nlast (updated|modified):[\s\S]*$/, "");
}

// Append a fresh footer. Body may be empty (footer-only) — every todo carries a stamp.
function stampDescription(desc) {
    const body = stripFooter(desc).replace(/\s+$/, "");
    const d = new Date();
    const p = n => String(n).padStart(2, "0");
    const stamp = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}: ${p(d.getHours())}:${p(d.getMinutes())}`;
    return `${body}\n\n\n----------\nlast modified: ${stamp}`;
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
        version: readVersion(),
    },
    {
        instructions: `Do-it.nvim todo list manager. Data lives at ~/.local/share/nvim/doit/lists/*.json — NOT in any project directory.

IMPORTANT: Always use these MCP tools for todo operations. NEVER use bash, grep, find, cat, or python to read/write todo JSON files directly. The tools handle all data access.

There is always an active list (usually "daily"). When the user says "show my todos", "what's next", "add a todo", or any todo-related request, use these tools directly — no filesystem discovery needed.

Session-linked lists: when this server runs inside tmux, the active list is PER TMUX SESSION. Resolution: DOIT_ACTIVE_LIST env > the current tmux session's link (the 'sessions' map in session.json) > the global pointer > "daily". Outside tmux only the global pointer applies.
- switch_list inside tmux links the current tmux session AND updates the global pointer by default; scope="global" sets only the global pointer, scope="session" only the link.
- create_list: the result text reports link state — if it auto-linked the new list to the current session, tell the user; if the session is already linked to another list, ASK the user before calling switch_list to relink. Never relink silently.
- list_lists shows which tmux sessions link each list — use it to answer "which session works on what".
- list_lists marks the active list "(via DOIT_ACTIVE_LIST env override ...)" when that env var decided it. Tell the user: a stale export in the shell that launched this server pins every session to one list, and the tmux link is what they expect.

Priorities: Items have a 'priorities' field with values: critical, urgent, important, or absent (default/no priority). Priority is a core workflow concept — the user works by priority most days.

Item text convention — MANDATORY for every item you create:

    claude: [type] N. body (dep on #M, #K)

- [type] — short lowercase work-type tag (decision, gate, loader, comms, bug, spike, chore, research, or a new one you coin). Pass it as add_todo's 'type' param, never hand-write the brackets. A bare list of sentences is unscannable; the tag is what makes it readable at a glance.
- N. — do-order rank across the whole list. Priority is the bucket (critical > urgent > important > default); N is the order INSIDE and ACROSS buckets, since a bucket with several items has no other visible ordering. add_todo assigns the next N automatically — do not write it into 'text'.
- (dep on #M) — pass blocking items as add_todo's 'deps' param, using their rank numbers (not ids). Blocked work must say so in the title, not only in the notes.
- claude: — keep this leading marker on items the model burns down via /burn; it stays in front of the type tag.

Retype or re-dep an existing item with update_todo's 'type' / 'deps' params; its rank is preserved.

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
- "switch to X list" → switch_list (in tmux: links this session + sets global; pass scope to narrow)
- "set the global list without touching this session" → switch_list with scope="global" (unlinking a session is done in the tmux UI with the u key)
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

Tags: written inline in the todo text as #tag — there is no tag field. Matching is exact, so #labels never matches #labels-web, and a tag may contain letters, digits, _, - and /.
- "what tags are on this list" → list_tags (name + how many items carry it)
- "show the #api todos" → list_todos with tag="api" (omit the '#')

Due dates: the 'due_date' field, "YYYY-MM-DD", shared with the nvim and tmux views.
- "due X by friday" → add_todo (or update_todo) with due="2026-08-21"
- "what's overdue" → list_todos with due="overdue"; also "today" and "week" (week spans overdue through the next 7 days)
- clear a due date with update_todo due=""

Nesting: a todo may hang off another via 'parent'. Ranks stay FLAT — N is still unique across the whole list, and a child gets its own N.
- "add X as a subtask of 3" → add_todo with parent=3 (a rank number or an id)
- "move X under Y" → update_todo with parent=<rank or id>; parent="" moves it back to the top level
- Deleting a parent does NOT delete its children: they are promoted to the top level. Completing a parent does not complete them either.

Duplicates: dedupe_todos removes items whose text matches after normalization (the claude: marker, [type] tag, rank prefix, (dep on #N) suffix, case and whitespace are all ignored, so an item typed in Neovim matches the same item created here). It is a DRY RUN by default — pass dry_run:false to actually delete.

The 'list' parameter is optional on MOST tools — omit it to use the active list, and only pass it when the user names a specific list. The exceptions:
- search_todos: no list param at all — it always searches every list.
- move_todo: uses 'from_list' (optional, defaults to active) and 'to_list' (required).
- switch_list: 'list' is required — it names the list to switch TO, not the one to act in.
- create_list and delete_list take 'name'; rename_list takes 'old_name' and 'new_name'.

Most tools that act on a single todo accept fuzzy text matching via 'query', so the user does not need the exact text or ID: start_todo, complete_todo, revert_todo, add_note, delete_todo, move_todo, and the note tools get_note / update_note / delete_note.

update_todo is the exception — it REQUIRES an id and has no 'query'. To act on an item the user described rather than identified, either use one of the fuzzy tools above, or call list_todos / search_todos first to get the id.`,
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
        tag: z.string().optional().describe("Filter by inline #tag, without the '#'. Exact match: 'labels' does not match 'labels-web'."),
        due: z.enum(["overdue", "today", "week"]).optional().describe("Filter by due date: overdue, due today, or due within 7 days (which includes overdue and today)."),
    },
    async ({ list, filter = "all", priority, tag, due }) => {
        const { name, data } = loadList(list);
        let todos = data.todos || [];

        if (filter === "pending") todos = todos.filter(t => !t.done && !t.in_progress);
        else if (filter === "done") todos = todos.filter(t => t.done);
        else if (filter === "in_progress") todos = todos.filter(t => t.in_progress);

        if (priority) {
            todos = todos.filter(t => t.priorities === priority);
        }

        if (tag) {
            const wanted = tag.replace(/^#/, "");
            todos = todos.filter(t => hasTag(t.text, wanted));
        }

        if (due) {
            todos = todos.filter(t => {
                const days = daysUntilDue(t.due_date);
                if (days === null) return false;
                if (due === "overdue") return days < 0;
                if (due === "today") return days === 0;
                return days <= 7; // "week" spans overdue through the next 7 days
            });
        }

        const lines = structureAware(todos).map(({ todo: t, depth }) => {
            const status = t.done ? "[x]" : t.in_progress ? "[~]" : "[ ]";
            const prio = t.priorities ? ` ${PRIORITY_LABELS[t.priorities] || t.priorities}` : "";
            const dueLabel = t.due_date ? ` [${renderDue(t.due_date)}]` : "";
            const indent = "  ".repeat(depth);
            let line = `${indent}${status}${prio} ${t.text}${dueLabel}  [id:${t.id}]`;
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
    "list_tags",
    "List the inline #tags used on a do-it list, with how many items carry each. Tags are parsed from todo text — there is no tag field. Counts cover active (not done) items by default, matching what the nvim and tmux tag pickers show.",
    {
        list: z.string().optional().describe("List name (default: active list)"),
        include_done: z.boolean().optional().describe("Also count tags on completed items (default: false)"),
    },
    async ({ list, include_done }) => {
        const { name, data } = loadList(list);
        const todos = (data.todos || []).filter(t => include_done || !t.done);

        const counts = new Map();
        for (const todo of todos) {
            for (const tag of parseTags(todo.text)) {
                counts.set(tag, (counts.get(tag) || 0) + 1);
            }
        }

        if (counts.size === 0) {
            return { content: [{ type: "text", text: `No tags on "${name}".` }] };
        }

        const rows = [...counts.entries()]
            .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
            .map(([tag, n]) => `#${tag}  (${n})`);

        return {
            content: [{
                type: "text",
                text: `Tags on "${name}":\n\n${rows.join("\n")}`,
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
    "Add a new todo item to a do-it list (writes to ~/.local/share/nvim/doit/lists/). Do not write JSON files directly. Stored text is composed as \"claude: [type] N. text (dep on #M)\" — pass type and deps as params, the rank N is assigned automatically.",
    {
        text: z.string().describe("Todo text. Omit the [type] prefix and the leading rank number — those are composed from the params below. Keep a leading 'claude:' if the item is for the model to burn down."),
        list: z.string().optional().describe("List name (default: active list)"),
        type: z.string().optional().describe("Work type." + TYPE_HINT),
        deps: z.array(z.union([z.number(), z.string()])).optional().describe("Blocking rank numbers." + DEPS_HINT),
        description: z.string().optional().describe("Multi-line notes/description." + NOTE_FORMAT_HINT),
        priority: z.enum(["critical", "urgent", "important"]).optional().describe("Priority level"),
        due: z.string().optional().describe("Due date as YYYY-MM-DD. Shared with the nvim and tmux views."),
        parent: z.union([z.number(), z.string()]).optional().describe("Nest under this item: its rank number (the leading N.) or its id. Ranks stay flat and unique across the whole list."),
        start: z.boolean().optional().describe("Immediately set as in_progress (default: false)"),
    },
    async ({ text, list, type, deps, description, priority, due, parent, start }) => {
        const { name, filepath, data } = loadList(list);
        const id = generateId();
        const composed = composeTodoText(text, { type, deps, rank: nextRank(data.todos || []) });
        const newTodo = {
            id,
            text: composed,
            done: false,
            in_progress: start || false,
            order_index: getMaxOrder(data.todos || []) + 1,
            created_at: Math.floor(Date.now() / 1000),
        };
        newTodo.description = stampDescription(description || "");
        if (priority) newTodo.priorities = priority;
        if (due) {
            if (!parseDue(due)) throw new Error(`Invalid due date "${due}". Use YYYY-MM-DD.`);
            newTodo.due_date = due;
        }
        if (parent !== undefined) {
            const parentTodo = resolveTodoRef(data.todos || [], parent);
            if (!parentTodo) throw new Error(`Parent "${parent}" not found in list "${name}".`);
            newTodo.parent_id = parentTodo.id;
            newTodo.depth = (parentTodo.depth || 0) + 1;
        }

        data.todos = data.todos || [];
        data.todos.push(newTodo);
        saveList(filepath, data);

        const status = start ? " (in_progress)" : "";
        return {
            content: [{
                type: "text",
                text: `Added to "${name}": ${composed}${status} [id:${id}]`,
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
        text: z.string().optional().describe("New text. The item's existing [type] prefix and rank number carry over — pass the body only."),
        type: z.string().optional().describe("Change the work type." + TYPE_HINT),
        deps: z.array(z.union([z.number(), z.string()])).optional().describe("Replace the blocking rank numbers." + DEPS_HINT),
        description: z.string().optional().describe("New description/notes." + NOTE_FORMAT_HINT),
        priority: z.enum(["critical", "urgent", "important", "none"]).optional().describe("Set priority level. Use 'none' to remove priority."),
        done: z.boolean().optional().describe("Set done status"),
        in_progress: z.boolean().optional().describe("Set in_progress status"),
        order_index: z.number().optional().describe("Set order position"),
        due: z.string().optional().describe("Set due date as YYYY-MM-DD. Use an empty string to clear it."),
        parent: z.union([z.number(), z.string()]).optional().describe("Re-nest under this item (rank number or id). Use an empty string to move it back to the top level."),
    },
    async ({ id, list, text, type, deps, description, priority, done, in_progress, order_index, due, parent }) => {
        const { name, filepath, data } = loadList(list);
        const todo = (data.todos || []).find(t => t.id === id);
        if (!todo) throw new Error(`Todo "${id}" not found in list "${name}"`);

        if (text !== undefined || type !== undefined || deps !== undefined) {
            todo.text = composeTodoText(text !== undefined ? text : todo.text, {
                type,
                deps,
                inherit: todo.text,
            });
        }
        if (description !== undefined) todo.description = stampDescription(description);
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
        if (parent !== undefined) {
            if (parent === "") {
                delete todo.parent_id;
                todo.depth = 0;
            } else {
                const parentTodo = resolveTodoRef(data.todos || [], parent);
                if (!parentTodo) throw new Error(`Parent "${parent}" not found in list "${name}".`);
                if (parentTodo.id === todo.id) throw new Error("A todo cannot be its own parent.");
                if (descendantIds(data.todos || [], todo.id).has(parentTodo.id)) {
                    throw new Error("That parent is inside this todo's own subtree, which would make a cycle.");
                }
                todo.parent_id = parentTodo.id;
                todo.depth = (parentTodo.depth || 0) + 1;
            }
        }
        if (due !== undefined) {
            if (due === "") {
                delete todo.due_date;
            } else if (!parseDue(due)) {
                throw new Error(`Invalid due date "${due}". Use YYYY-MM-DD.`);
            } else {
                todo.due_date = due;
            }
        }

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
        note: z.string().describe("Note text to add to the todo item." + NOTE_FORMAT_HINT),
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
            todo.description = stampDescription(note);
        } else {
            todo.description = stampDescription(stripFooter(todo.description).trimEnd() + "\n\n" + note);
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
        // incomplete children outlive their parent (no completion cascade)
        promoteChildren(data.todos, data.todos[idx].id);
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

        for (const t of done) promoteChildren(data.todos, t.id);
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

server.tool(
    "dedupe_todos",
    "Remove duplicate todos from a list. Duplicates are items whose text matches after normalization — the claude: marker, [type] tag, rank prefix and (dep on #N) suffix are ignored, so an item typed in nvim matches the same item created here. Defaults to a DRY RUN that only reports what it would remove; pass dry_run:false to actually delete. Ranks are not renumbered.",
    {
        list: z.string().optional().describe("List name (default: active list)"),
        dry_run: z
            .boolean()
            .optional()
            .describe("Report without deleting (default: true). Pass false to delete."),
    },
    async ({ list, dry_run }) => {
        const dryRun = dry_run !== false;
        const { name, filepath, data } = loadList(list);
        const todos = data.todos || [];

        // first occurrence in order_index order is the keeper, so repeated runs
        // are stable; a copy carrying notes wins over a bare one
        const ordered = [...todos].sort((a, b) => (a.order_index || 0) - (b.order_index || 0));
        const groups = new Map();
        for (const todo of ordered) {
            const key = normalizeTodoText(todo.text);
            if (!key) continue; // an empty body carries no identity
            if (!groups.has(key)) groups.set(key, []);
            groups.get(key).push(todo);
        }

        const removed = [];
        const report = [];
        for (const [, items] of groups) {
            if (items.length < 2) continue;
            // every todo carries a footer stamp, so "has a description" is always
            // true — the tie-break has to look past the footer at real notes
            const hasNotes = t => Boolean(stripFooter(t.description).trim());
            const keepIdx = items.findIndex(hasNotes);
            const keeper = items[keepIdx === -1 ? 0 : keepIdx];
            const drops = items.filter(t => t !== keeper);
            removed.push(...drops);
            report.push(
                `keep: ${keeper.text}` +
                    drops.map(d => `\n  drop: ${d.text}${hasNotes(d) ? " (HAS NOTES)" : ""}`).join("")
            );
        }

        if (removed.length === 0) {
            return { content: [{ type: "text", text: `No duplicates on "${name}".` }] };
        }

        if (dryRun) {
            return {
                content: [{
                    type: "text",
                    text:
                        `DRY RUN — would remove ${removed.length} duplicate(s) from "${name}":\n\n` +
                        report.join("\n\n") +
                        `\n\nRe-run with dry_run:false to apply.`,
                }],
            };
        }

        const dropIds = new Set(removed.map(t => t.id));
        data.todos = todos.filter(t => !dropIds.has(t.id));
        data._metadata = data._metadata || {};
        data._metadata.deleted_todos = [...removed, ...(data._metadata.deleted_todos || [])].slice(0, 10);
        saveList(filepath, data);

        return {
            content: [{
                type: "text",
                text: `Removed ${removed.length} duplicate(s) from "${name}":\n\n${report.join("\n\n")}`,
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
        // the subtree stays behind, promoted, rather than following across lists
        promoteChildren(source.data.todos, source.data.todos[idx].id);
        const [moved] = source.data.todos.splice(idx, 1);
        delete moved.parent_id;
        moved.depth = 0;

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
        const activeVia = process.env.DOIT_ACTIVE_LIST
            ? " (via DOIT_ACTIVE_LIST env override, not the session link)"
            : "";

        const linksByList = {};
        for (const [sess, list] of Object.entries(readSession().sessions || {})) {
            (linksByList[list] = linksByList[list] || []).push(sess);
        }

        const lines = files.map(f => {
            const name = f.replace(/\.json$/, "");
            const data = readJSON(path.join(LISTS_DIR, f));
            const total = (data.todos || []).length;
            const pending = (data.todos || []).filter(t => !t.done).length;
            const linked = linksByList[name] ? ` (linked: ${linksByList[name].join(", ")})` : "";
            const marker = name === active ? ` <-- active${activeVia}` : "";
            return `${name}: ${pending} pending / ${total} total${linked}${marker}`;
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
    "Switch the active do-it list. Inside tmux the default links the current tmux session to the list AND updates the global pointer; scope narrows the write.",
    {
        list: z.string().describe("List name to switch to"),
        scope: z.enum(["session", "global"]).optional().describe("'session': only link the current tmux session (needs tmux). 'global': only set the global pointer, touch no session link. Omit for the default (both inside tmux, global outside)."),
    },
    async ({ list, scope }) => {
        const filepath = getListPath(list);
        if (!fs.existsSync(filepath)) {
            throw new Error(`List "${list}" not found. Use list_lists to see available lists.`);
        }

        const sess = getTmuxSessionName();
        if (scope === "session" && !sess) {
            throw new Error("Not inside tmux — there is no session to link. Use scope 'global' or omit scope.");
        }

        const linkIt = scope !== "global" && sess;
        const setGlobal = scope !== "session";
        updateSession(session => {
            if (linkIt) {
                session.sessions = session.sessions || {};
                session.sessions[sess] = list;
            }
            if (setGlobal) session.active_list = list;
        });

        const effects = [];
        if (linkIt) effects.push(`linked tmux session "${sess}"`);
        if (setGlobal) effects.push("set the global pointer");
        return {
            content: [{
                type: "text",
                text: `Switched active list to "${list}" (${effects.join(" and ")})`,
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

        let sessionNote = "";
        const sess = getTmuxSessionName();
        if (sess) {
            const existing = (readSession().sessions || {})[sess];
            if (!existing) {
                updateSession(session => {
                    session.sessions = session.sessions || {};
                    session.sessions[sess] = name;
                });
                sessionNote = `\ntmux session "${sess}" had no linked list, so "${name}" is now linked to it (it is this session's active list). Tell the user.`;
            } else if (existing !== name) {
                sessionNote = `\ntmux session "${sess}" is currently linked to "${existing}". Do NOT relink it yourself — ask the user whether this session should switch to "${name}" (then call switch_list).`;
            }
        }

        return {
            content: [{
                type: "text",
                text: `Created list "${name}" at ${filepath}${sessionNote}`,
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

        updateSession(session => {
            for (const [sess, list] of Object.entries(session.sessions || {})) {
                if (list === old_name) session.sessions[sess] = new_name;
            }
        });

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

        updateSession(session => {
            for (const [sess, list] of Object.entries(session.sessions || {})) {
                if (list === name) delete session.sessions[sess];
            }
        });

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
