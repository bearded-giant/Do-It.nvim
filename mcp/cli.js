#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { execFileSync } from "child_process";
import { fileURLToPath } from "url";
import { parseArgs, styleText } from "util";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import {
    confirm as confirmPrompt, editor, input as inputPrompt, search as searchPrompt, select as selectPrompt, Separator,
} from "@inquirer/prompts";
import {
    LISTS_DIR, PRIORITY_LABELS, findListByTodoId, isMineList, loadList, parseDue, readJSON, readVersion,
    renderDue, server, setItemSource, stripFooter, structureAware,
} from "./server.js";
import { isSequenced } from "./sequence.js";
import { parseTodoText } from "./todo-text.js";

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const interactive = Boolean(process.stdin.isTTY && process.stdout.isTTY);
const PRIORITIES = ["critical", "urgent", "important"];
const PRIORITY_RANK = { critical: 0, urgent: 1, important: 2 };

const HELP = `doit ${readVersion()}

Usage: doit [command] [options]

Browse
  doit                          pick a list, then browse and edit its items
  doit open [list]              browse one list
  doit find <text>              search items on every list

Lists
  doit lists [filter]           print lists (--mine, --claude)
  doit list add <name>          create a list
  doit list rename <old> <new>  rename a list
  doit list rm <name>           delete a list (archived under deleted/)
  doit list use <name>          make it the current list (links this tmux window)

Items
  doit ls [list]                print a list's items (-a includes done)
  doit add [text]               add an item; prompts for anything missing
  doit show <item>              print an item with its notes
  doit edit <item>              edit interactively, or with --title -p --due -t -d
  doit note <item> [text]       append a note ($EDITOR, or stdin when piped)
  doit start|done|reopen <item> change status
  doit mv <item> [list]         move to another list
  doit rm <item>                delete

<item> is an id, a #rank, or words from its text (quote it when more follows).
With no <item>, commands that need one let you pick it.

Options
  -l, --list <name>       list to use (default: the current list)
  -t, --type <tag>        work type tag, e.g. chore
  -p, --priority <level>  critical, urgent, important (edit also takes none)
      --due <date>        YYYY-MM-DD (edit takes none to clear)
  -d, --desc <text>       item details
      --title <text>      new title (edit)
      --parent <item>     nest under this item (add)
      --start             start the new item (add)
  -a, --all               include done items
      --mine, --claude    only lists of that source
  -y, --yes               skip confirmations
  -h, --help              show this help
  -v, --version           print the version`;

const OPTIONS = {
    list: { type: "string", short: "l" },
    type: { type: "string", short: "t" },
    priority: { type: "string", short: "p" },
    due: { type: "string" },
    desc: { type: "string", short: "d" },
    title: { type: "string" },
    parent: { type: "string" },
    start: { type: "boolean" },
    all: { type: "boolean", short: "a" },
    mine: { type: "boolean" },
    claude: { type: "boolean" },
    yes: { type: "boolean", short: "y" },
    help: { type: "boolean", short: "h" },
    version: { type: "boolean", short: "v" },
};

const dim = s => styleText("dim", s);
const firstLine = s => (s || "").split("\n")[0];
const success = msg => msg && console.log(`${styleText(["green", "bold"], "Success!")} ${msg}`);
const isAbort = err => err?.name === "AbortPromptError";
const BACK = Symbol("back");

function fail(err) {
    console.error(`${styleText("red", "Error:", { stream: process.stderr })} ${err.message}`);
}

const keysHelpTip = keys =>
    [...keys, ["esc", "back"]].map(([key, action]) => `${styleText("bold", key)} ${dim(action)}`).join(dim(" • "));

// inquirer has no Esc binding, so Esc aborts the open prompt: menus read that as back, actions as cancel
function escapable(prompt) {
    return async config => {
        const ac = new AbortController();
        const onKey = (_, key) => key?.name === "escape" && ac.abort();
        process.stdin.on("keypress", onKey);
        try {
            return await prompt({ ...config, theme: { style: { keysHelpTip } } }, { signal: ac.signal });
        } finally {
            process.stdin.off("keypress", onKey);
        }
    };
}
const [confirm, input, search, select] = [confirmPrompt, inputPrompt, searchPrompt, selectPrompt].map(escapable);

const orBack = promise => promise.catch(err => {
    if (isAbort(err)) return BACK;
    throw err;
});

// every write goes through the MCP tools, so twin sync, stamps and validation stay in one place
setItemSource("user");
let client;
async function call(name, args) {
    if (!client) {
        const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
        await server.connect(serverSide);
        client = new Client({ name: "doit-cli", version: readVersion() });
        await client.connect(clientSide);
    }
    const res = await client.callTool({ name, arguments: args });
    const text = (res.content || []).map(c => c.text).join("\n");
    if (res.isError) throw new Error(text);
    return text;
}

function ask(prompt, config, what) {
    if (!interactive) throw new Error(`Missing ${what}. Run doit --help.`);
    return prompt(config);
}

async function guard(fn) {
    try {
        return await fn();
    } catch (err) {
        if (err?.name === "ExitPromptError") throw err;
        if (!isAbort(err)) fail(err);
        return undefined;
    }
}

function matchesWords(hay, term) {
    const h = (hay || "").toLowerCase();
    return (term || "").toLowerCase().split(/\s+/).filter(Boolean).every(w => h.includes(w));
}

// --- lists ---

function listNames() {
    if (!fs.existsSync(LISTS_DIR)) return [];
    return fs.readdirSync(LISTS_DIR).filter(f => f.endsWith(".json")).map(f => f.slice(0, -5));
}

let current;
// the list this tmux window shows, resolved by the script the tmux views use
function currentList() {
    if (current) return current;
    try {
        current = execFileSync("bash", [path.join(ROOT, "tmux/scripts/get-active-list.sh"), "name"], {
            encoding: "utf-8",
            stdio: ["ignore", "pipe", "ignore"],
        }).trim();
    } catch {
        current = "";
    }
    return (current ||= "daily");
}

function sortedLists({ filter, mine, claude, exclude } = {}) {
    const cur = currentList();
    const weight = l => (l.current ? 0 : 100) + (l.name === "daily" ? 0 : 10) + (l.active ? 0 : l.open ? 1 : 2);
    return listNames()
        .filter(name => name !== exclude && matchesWords(name, filter))
        .map(name => {
            const data = readJSON(path.join(LISTS_DIR, `${name}.json`));
            const todos = data.todos || [];
            return {
                name,
                current: name === cur,
                mine: isMineList(name, data),
                open: todos.filter(t => !t.done).length,
                total: todos.length,
                active: todos.find(t => t.in_progress && !t.done),
            };
        })
        .filter(l => (!mine || l.mine) && (!claude || !l.mine))
        .sort((a, b) => weight(a) - weight(b) || a.name.localeCompare(b.name));
}

function listRow(l, width) {
    const marker = l.current ? styleText("green", "●") : " ";
    const open = l.open ? `${l.open} open` : dim("empty");
    return `${marker} ${l.name.padEnd(width)}  ${dim((l.mine ? "mine" : "claude").padEnd(6))}  ${open}`;
}

function printLists(o) {
    const lists = sortedLists(o);
    const width = Math.max(4, ...lists.map(l => l.name.length));
    console.log(`> ${lists.length} list${lists.length === 1 ? "" : "s"}\n`);
    console.log(dim(`  ${"name".padEnd(width)}  source  open  total  in progress`));
    for (const l of lists) {
        const src = (l.mine ? "mine" : "claude").padEnd(6);
        const counts = `${String(l.open).padStart(4)}  ${String(l.total).padStart(5)}`;
        console.log(`${l.current ? styleText("green", "●") : " "} ${l.name.padEnd(width)}  ${src}  ${counts}  ${firstLine(l.active?.text)}`);
    }
}

async function pickList({ message = "Which list?", create, quit, term, ...filters } = {}) {
    const lists = sortedLists(filters);
    const width = Math.max(4, ...lists.map(l => l.name.length));
    const picked = await search({
        message,
        pageSize: 15,
        initialValue: term,
        source: raw => {
            const q = (raw || "").trim();
            const rows = lists.filter(l => matchesWords(l.name, q)).map(l => ({
                value: l.name,
                name: listRow(l, width),
                short: l.name,
                description: l.active ? `in progress: ${firstLine(l.active.text)}` : undefined,
            }));
            const extra = [];
            if (quit && matchesWords("quit", q)) extra.push({ value: { quit: true }, name: "quit" });
            if (create) extra.push({ value: { create: q }, name: q ? `+ new list "${q}"` : "+ new list" });
            return rows.length && extra.length ? [...rows, new Separator(), ...extra] : [...rows, ...extra];
        },
    });
    if (typeof picked === "string") return picked;
    return picked.quit ? null : createList(picked.create);
}

async function existingList(name, o) {
    if (fs.existsSync(path.join(LISTS_DIR, `${name}.json`))) return name;
    if (!interactive) throw new Error(`List "${name}" not found.`);
    return pickList({ ...o, term: name, create: true });
}

async function createList(name) {
    name ||= await ask(input, { message: "List name", required: true }, "list name");
    success(await call("create_list", { name }));
    return name;
}

async function renameList(name) {
    name ||= await ask(pickList, { message: "Rename which list?" }, "list name");
    const to = await ask(input, { message: "New name", default: name, prefill: "editable", required: true }, "new name");
    success(await call("rename_list", { old_name: name, new_name: to }));
    return to;
}

async function deleteList(name, yes) {
    name ||= await ask(pickList, { message: "Delete which list?" }, "list name");
    const message = `Delete list "${name}"? It moves to deleted/ under the data dir.`;
    if (!yes && !(await ask(confirm, { message, default: false }, "--yes"))) return false;
    success(await call("delete_list", { name }));
    return true;
}

async function useList(name) {
    name ||= await ask(pickList, { message: "Make which list current?" }, "list name");
    success(await call("switch_list", { list: name }));
    current = name;
}

async function listCommand([verb = "ls", ...args], o) {
    if (verb === "ls") return printLists({ ...o, filter: args.join(" ") });
    if (verb === "add") return createList(args[0]);
    if (verb === "open") return browse(o, args[0] && (await existingList(args[0], o)));
    if (verb === "rename") {
        if (!args[1]) return renameList(args[0]);
        return success(await call("rename_list", { old_name: args[0], new_name: args[1] }));
    }
    if (verb === "rm") return deleteList(args[0], o.yes);
    if (verb === "use") return useList(args[0]);
    throw new Error(`Unknown list command "${verb}". Run doit --help.`);
}

async function listActions(name) {
    const action = await select({
        message: name,
        choices: [
            { value: "use", name: "make current (links this tmux window)" },
            { value: "rename", name: "rename" },
            { value: "clear", name: "clear done items" },
            { value: "rm", name: "delete list" },
            { value: "back", name: "back" },
        ],
    });
    if (action === "use") await useList(name);
    if (action === "rename") return renameList(name);
    if (action === "clear" && (await confirm({ message: "Clear done items?", default: false }))) {
        success(await call("clear_done", { list: name }));
    }
    if (action === "rm") return (await deleteList(name)) ? null : name;
    return name;
}

// --- items ---

// structureAware keeps each subtree contiguous; whole subtrees then sort by their root like the nvim sections
function orderedRows(data, showDone) {
    const rows = structureAware((data.todos || []).filter(t => showDone || !t.done));
    const trees = [];
    for (const row of rows) {
        if (row.depth === 0 || !trees.length) trees.push([row]);
        else trees.at(-1).push(row);
    }
    const bucket = t => (t.done ? 6 : t.in_progress ? 0 : isSequenced(t) ? 1 : 2 + (PRIORITY_RANK[t.priorities] ?? 3));
    return trees.sort((a, b) => bucket(a[0].todo) - bucket(b[0].todo)).flat();
}

function todoRow({ todo: t, depth }) {
    const status = t.done ? "[x]" : t.in_progress ? styleText("yellow", "[~]") : "[ ]";
    const prio = t.priorities ? ` ${styleText("red", PRIORITY_LABELS[t.priorities] || t.priorities)}` : "";
    const due = renderDue(t.due_date);
    const dueLabel = due ? ` ${styleText(due.startsWith("overdue") ? "red" : "dim", `(${due})`)}` : "";
    const seq = isSequenced(t) ? dim(` [seq ${t.sequence}]`) : "";
    const row = `${"  ".repeat(depth)}${status}${prio} ${firstLine(t.text)}${dueLabel}${seq}`;
    return t.done ? dim(row) : row;
}

function printItems(name, showDone) {
    const { data } = loadList(name);
    const todos = data.todos || [];
    const rows = orderedRows(data, showDone);
    console.log(`> ${name}  ${todos.filter(t => !t.done).length} open / ${todos.length}\n`);
    for (const r of rows) console.log(`  ${todoRow(r)}  ${dim(r.todo.id)}`);
    if (!rows.length) console.log(dim(showDone ? "  (empty)" : "  (no open items)"));
    const notes = (data.notes || []).length;
    if (notes) console.log(dim(`\n  ${notes} list note${notes === 1 ? "" : "s"}`));
}

async function pickItem(list, includeDone) {
    if (!interactive) throw new Error("Missing <item>. Run doit --help.");
    const rows = orderedRows(loadList(list).data, includeDone);
    if (!rows.length) throw new Error(`"${list}" has no ${includeDone ? "" : "open "}items.`);
    const id = await search({
        message: `Which item on ${list}?`,
        pageSize: 20,
        source: term => rows
            .filter(r => matchesWords(r.todo.text, term))
            .map(r => ({ value: r.todo.id, name: todoRow(r), short: firstLine(r.todo.text) })),
    });
    return rows.find(r => r.todo.id === id).todo;
}

async function resolveItem(ref, o, includeDone = false) {
    ref = (ref || "").trim();
    if (!ref) return pickItem(o.list || currentList(), includeDone);

    const byId = findListByTodoId(ref);
    if (byId) return byId.data.todos.find(t => t.id === ref);

    const rank = /^#?(\d+)$/.exec(ref);
    if (rank) {
        const list = o.list || currentList();
        const hit = (loadList(list).data.todos || []).find(t => parseTodoText(t.text).rank === Number(rank[1]));
        if (hit) return hit;
    }

    const hits = (o.list ? [o.list] : listNames()).flatMap(list =>
        (loadList(list).data.todos || [])
            .filter(t => (includeDone || !t.done) && matchesWords(t.text, ref))
            .map(todo => ({ list, todo })));
    if (hits.length === 1) return hits[0].todo;
    if (!hits.length) throw new Error(`No ${includeDone ? "" : "open "}item matches "${ref}".`);
    if (!interactive) {
        const lines = hits.map(h => `  ${h.todo.id}  ${h.list}: ${firstLine(h.todo.text)}`);
        throw new Error(`"${ref}" matches ${hits.length} items, pass an id:\n${lines.join("\n")}`);
    }
    return select({
        message: "Which item?",
        choices: hits.map(h => ({ value: h.todo, name: `${dim(h.list)}  ${firstLine(h.todo.text)}` })),
    });
}

async function addItem({ list, text, type, priority, due, description, parent, start, askPriority }) {
    list ||= text || !interactive ? currentList() : await pickList({ message: "Add to which list?", create: true });
    text ||= await ask(input, { message: "Title", required: true }, "item text");
    if (askPriority && priority === undefined) {
        priority = await select({ message: "Priority", choices: ["none", ...PRIORITIES] });
    }
    if (priority === "none") priority = undefined;
    return call("add_todo", { list, text, type, priority, due, description, parent, start });
}

async function askNote() {
    const text = await input({ message: "Note (empty opens $EDITOR)" });
    return text.trim() ? text : editor({ message: "Note", postfix: ".md", waitForUserInput: false });
}

async function addNote(todo, text) {
    if (!text.trim()) throw new Error("Empty note, nothing added.");
    const out = await call("add_note", { id: todo.id, note: text.trimEnd() });
    return out.split("\n\nFull note:")[0];
}

const validDue = v => ["", "none"].includes(v.trim()) || Boolean(parseDue(v.trim())) || "Use a real YYYY-MM-DD date, or none";

const ITEM_ACTIONS = {
    start: t => call("start_todo", { id: t.id }),
    done: t => call("complete_todo", { id: t.id }),
    reopen: t => call("revert_todo", { id: t.id }),
    note: async t => addNote(t, await askNote()),
    details: async t => call("update_todo", {
        id: t.id,
        description: await editor({
            message: "Details",
            default: stripFooter(t.description).trim(),
            postfix: ".md",
            waitForUserInput: false,
        }),
    }),
    title: async t => call("update_todo", {
        id: t.id,
        text: await input({ message: "Title", default: parseTodoText(t.text).body, prefill: "editable", required: true }),
    }),
    priority: async t => call("update_todo", {
        id: t.id,
        priority: await select({ message: "Priority", default: t.priorities || "none", choices: [...PRIORITIES, "none"] }),
    }),
    due: async t => {
        const raw = await input({
            message: "Due date (YYYY-MM-DD, none clears)",
            default: t.due_date,
            prefill: "editable",
            validate: validDue,
        });
        const due = raw.trim() === "none" ? "" : raw.trim();
        return due === (t.due_date || "") ? null : call("update_todo", { id: t.id, due });
    },
    type: async t => {
        const type = (await input({ message: "Type tag", default: parseTodoText(t.text).type || "" })).trim();
        return type ? call("update_todo", { id: t.id, type }) : null;
    },
    sub: (t, list) => addItem({ list, parent: t.id, askPriority: true }),
    move: async (t, list) => call("move_todo", {
        id: t.id,
        to_list: await pickList({ message: "Move to which list?", exclude: list }),
    }),
    rm: async t => ((await confirm({ message: `Delete "${firstLine(t.text)}"?`, default: false }))
        ? call("delete_todo", { id: t.id })
        : null),
};

async function openItem(id) {
    for (;;) {
        const found = findListByTodoId(id);
        if (!found) return;
        const todo = found.data.todos.find(t => t.id === id);
        console.log(`\n${await call("get_todo", { id })}\n`);
        const status = todo.done
            ? [{ value: "reopen", name: "reopen" }]
            : todo.in_progress
                ? [{ value: "done", name: "complete" }, { value: "reopen", name: "stop (back to pending)" }]
                : [{ value: "start", name: "start" }, { value: "done", name: "complete" }];
        const action = await orBack(select({
            message: firstLine(todo.text),
            pageSize: 16,
            choices: [
                ...status,
                { value: "note", name: "add note" },
                { value: "details", name: "edit details" },
                { value: "title", name: "edit title" },
                { value: "priority", name: `priority (${todo.priorities || "none"})` },
                { value: "due", name: `due date (${todo.due_date || "none"})` },
                { value: "type", name: `type (${parseTodoText(todo.text).type || "none"})` },
                { value: "sub", name: "add subtask" },
                { value: "move", name: "move to list" },
                { value: "rm", name: "delete" },
                new Separator(),
                { value: "back", name: "back" },
            ],
        }));
        if (action === "back" || action === BACK) return;
        const out = await guard(() => ITEM_ACTIONS[action](todo, found.name));
        success(out);
        if (action === "rm" && out) return;
    }
}

// --- list notes ---

async function newNote(list) {
    const title = await input({ message: "Title", required: true });
    const body = await editor({ message: "Body", postfix: ".md", waitForUserInput: false });
    return call("create_note", { list, title, body });
}

async function noteActions(list, note) {
    console.log(`\n${await call("get_note", { list, id: note.id })}\n`);
    const action = await select({
        message: note.title,
        choices: [
            { value: "body", name: "edit body" },
            { value: "title", name: "rename" },
            { value: "rm", name: "delete" },
            { value: "back", name: "back" },
        ],
    });
    if (action === "body") {
        const body = await editor({ message: "Body", default: note.body || "", postfix: ".md", waitForUserInput: false });
        return call("update_note", { list, id: note.id, body });
    }
    if (action === "title") {
        const title = await input({ message: "Title", default: note.title, prefill: "editable", required: true });
        return call("update_note", { list, id: note.id, title });
    }
    if (action === "rm" && (await confirm({ message: `Delete note "${note.title}"?`, default: false }))) {
        return call("delete_note", { list, id: note.id });
    }
    return null;
}

async function openNotes(list) {
    for (;;) {
        const notes = loadList(list).data.notes || [];
        const id = await orBack(select({
            message: `${list} notes`,
            pageSize: 15,
            choices: [
                ...notes.map(n => ({ value: n.id, name: n.title })),
                ...(notes.length ? [new Separator()] : []),
                { value: "new", name: "+ new note" },
                { value: "back", name: "back" },
            ],
        }));
        if (id === "back" || id === BACK) return;
        success(await guard(() => (id === "new" ? newNote(list) : noteActions(list, notes.find(n => n.id === id)))));
    }
}

// --- browse ---

async function openList(name) {
    let showDone = false;
    while (name) {
        const { data } = loadList(name);
        const todos = data.todos || [];
        const open = todos.filter(t => !t.done).length;
        const rows = orderedRows(data, showDone);
        const choice = await orBack(search({
            message: `${name} ${dim(`${open} open / ${todos.length}`)}`,
            pageSize: 20,
            source: raw => {
                const q = (raw || "").trim();
                const items = rows
                    .filter(r => matchesWords(r.todo.text, q))
                    .map(r => ({ value: { id: r.todo.id }, name: todoRow(r), short: firstLine(r.todo.text) }));
                const add = { value: { add: q }, name: q ? `+ add "${q}"` : "+ add item" };
                // typed text that names an action reaches it before the add, so Enter never adds "show done"
                const actions = [
                    { value: { notes: true }, name: `list notes (${(data.notes || []).length})` },
                    { value: { toggleDone: true }, name: showDone ? "hide done" : `show done (${todos.length - open})` },
                    { value: { manage: true }, name: "list actions" },
                    { value: { back: true }, name: "back to lists" },
                ].filter(a => matchesWords(a.name, q));
                const tail = q ? [...actions, add] : [add, ...actions];
                return items.length ? [...items, new Separator(), ...tail] : tail;
            },
        }));
        if (choice === BACK || choice.back) return;
        if (choice.toggleDone) {
            showDone = !showDone;
            continue;
        }
        await guard(async () => {
            if (choice.id) await openItem(choice.id);
            else if (choice.notes) await openNotes(name);
            else if (choice.manage) name = await listActions(name);
            else success(await addItem({ list: name, text: choice.add || undefined, askPriority: true }));
        });
    }
}

async function browse(o, start) {
    console.error(dim(`doit ${readVersion()}`));
    let name = start;
    for (;;) {
        if (!name) {
            name = await guard(() => orBack(pickList({ ...o, create: true, quit: true })));
            if (name === null || name === BACK) return;
        }
        if (name) await openList(name);
        name = undefined;
    }
}

async function find(query, o) {
    query ||= await ask(input, { message: "Search", required: true }, "search text");
    const hits = listNames().flatMap(list =>
        (loadList(list).data.todos || [])
            .filter(t => (o.all || !t.done) && matchesWords(`${t.text} ${stripFooter(t.description)}`, query))
            .map(todo => ({ list, todo })));
    if (!hits.length) return console.log(`> No ${o.all ? "" : "open "}items match "${query}".`);
    const width = Math.max(...hits.map(h => h.list.length));
    const rows = hits.map(h => ({ ...h, label: `${dim(h.list.padEnd(width))}  ${todoRow({ todo: h.todo, depth: 0 })}` }));
    if (!interactive) {
        for (const r of rows) console.log(`${r.label}  ${dim(r.todo.id)}`);
        return;
    }
    const id = await select({
        message: `${hits.length} match${hits.length === 1 ? "" : "es"} for "${query}"`,
        pageSize: 20,
        choices: rows.map(r => ({ value: r.todo.id, name: r.label, short: firstLine(r.todo.text) })),
    });
    return openItem(id);
}

// --- commands ---

async function editItem(ref, o) {
    const todo = await resolveItem(ref, o, true);
    const changes = {};
    if (o.title !== undefined) changes.text = o.title;
    if (o.type !== undefined) changes.type = o.type;
    if (o.priority !== undefined) changes.priority = o.priority;
    if (o.due !== undefined) changes.due = o.due === "none" ? "" : o.due;
    if (o.desc !== undefined) changes.description = o.desc;
    if (Object.keys(changes).length) return success(await call("update_todo", { id: todo.id, ...changes }));
    if (!interactive) throw new Error("Nothing to change: pass --title, -p, --due, -t or -d.");
    return openItem(todo.id);
}

const STATUS_TOOLS = { start: "start_todo", done: "complete_todo", reopen: "revert_todo" };

async function main() {
    const { values: o, positionals } = parseArgs({ allowPositionals: true, options: OPTIONS });
    if (o.version) return console.log(readVersion());
    const [cmd = "", ...args] = positionals;
    if (o.help || cmd === "help") return console.log(HELP);
    const rest = args.join(" ");

    switch (cmd) {
        case "":
            return interactive ? browse(o) : printLists(o);
        case "open":
            return browse(o, args[0] && (await existingList(args[0], o)));
        case "lists":
            return printLists({ ...o, filter: rest });
        case "list":
            return listCommand(args, o);
        case "find":
            return find(rest, o);
        case "ls":
            return printItems(args[0] || o.list || currentList(), o.all);
        case "add":
            return success(await addItem({
                list: o.list,
                text: rest || undefined,
                type: o.type,
                priority: o.priority,
                due: o.due,
                description: o.desc,
                parent: o.parent,
                start: o.start,
                askPriority: interactive && !rest,
            }));
        case "show":
            return console.log(await call("get_todo", { id: (await resolveItem(rest, o, true)).id }));
        case "edit":
            return editItem(rest, o);
        case "note": {
            const [ref, ...words] = args;
            const todo = await resolveItem(ref, o);
            let text = words.join(" ");
            if (!text) text = interactive ? await askNote() : fs.readFileSync(0, "utf-8");
            return success(await addNote(todo, text));
        }
        case "start":
        case "done":
        case "reopen": {
            const todo = await resolveItem(rest, o, cmd === "reopen");
            return success(await call(STATUS_TOOLS[cmd], { id: todo.id }));
        }
        case "mv": {
            const todo = await resolveItem(args[0], o);
            const to = args[1] || (await ask(pickList, { message: "Move to which list?" }, "target list"));
            return success(await call("move_todo", { id: todo.id, to_list: to }));
        }
        case "rm": {
            const todo = await resolveItem(rest, o, true);
            const message = `Delete "${firstLine(todo.text)}"?`;
            if (!o.yes && !(await ask(confirm, { message, default: false }, "--yes"))) return;
            return success(await call("delete_todo", { id: todo.id }));
        }
        default:
            throw new Error(`Unknown command "${cmd}". Run doit --help.`);
    }
}

main().catch(err => {
    if (err?.name === "ExitPromptError" || isAbort(err)) {
        process.exitCode = 130;
        return;
    }
    fail(err);
    process.exitCode = 1;
});
