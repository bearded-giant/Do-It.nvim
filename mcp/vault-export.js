#!/usr/bin/env node

// One-way export of every list into an Obsidian vault folder: a dir per list,
// a note per item, so lists can be browsed, linked, and read beside other notes.

import fs from "fs";
import path from "path";
import { execFileSync } from "child_process";
import { fileURLToPath } from "url";
import { isSequenced } from "./sequence.js";
import { normalizeTodoText, parseDeps, parseTags, parseTodoText } from "./todo-text.js";

const DATA_DIR = process.env.DOIT_DATA_DIR || path.join(process.env.HOME, ".local/share/nvim/doit");
const LISTS_DIR = path.join(DATA_DIR, "lists");
const AGENT_LABEL = "com.doit.vault-export";
const USAGE = "usage: vault-export.js <out_dir> [--watch | --install]";

const PRIORITY_LABELS = { critical: "!!!", urgent: "!!", important: "!" };
const PRIORITY_RANK = { critical: 0, urgent: 1, important: 2 };
const FOOTER = /\n*-{10}\nlast [a-z]+:\s*([^\n]*)\s*$/;
// only notes carrying this key are pruned, so files the user drops in the folder survive
const GENERATED = /^---\n(?:.*\n)*?doit_list: /;

function slugify(text) {
    const slug = text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    return slug.length > 48 ? slug.slice(0, 48).replace(/-[^-]*$/, "") : slug;
}

function stamp(epoch) {
    const n = Number(epoch);
    if (!n) return undefined;
    const d = new Date(n * 1000);
    const p = v => String(v).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

const label = text => text.replace(/[[\]|]/g, " ").replace(/\s+/g, " ").trim();

// JSON strings are valid YAML double-quoted scalars, so values like "2026-10-15: 20:49" stay intact
function frontmatter(fields) {
    const value = v => (Array.isArray(v) ? `[${v.map(x => JSON.stringify(x)).join(", ")}]` : typeof v === "string" ? JSON.stringify(v) : v);
    const lines = Object.entries(fields)
        .filter(([, v]) => v !== undefined && v !== null && v !== "" && v !== false)
        .map(([k, v]) => `${k}: ${value(v)}`);
    return `---\n${lines.join("\n")}\n---\n`;
}

function status(todo) {
    return todo.done ? "done" : todo.in_progress ? "in_progress" : "pending";
}

function pendingOrder(a, b) {
    const sa = isSequenced(a.todo);
    const sb = isSequenced(b.todo);
    if (sa !== sb) return sa ? -1 : 1;
    if (sa) return a.todo.sequence - b.todo.sequence;
    return (
        (PRIORITY_RANK[a.todo.priorities] ?? 3) - (PRIORITY_RANK[b.todo.priorities] ?? 3) ||
        (a.todo.order_index ?? 0) - (b.todo.order_index ?? 0)
    );
}

function place(name, entries, slugOf, dirOf) {
    const used = new Set([name]);
    return entries.map(entry => {
        const base = slugOf(entry) || "item";
        const file = used.has(base) ? `${base}-${String(entry.id).slice(-4)}` : base;
        used.add(file);
        return { entry, rel: `${name}/${dirOf(entry)}${file}` };
    });
}

function renderItem(list, { todo, parsed }, linkTo, idByRank) {
    const [title, ...rest] = parsed.body.split("\n");
    const description = todo.description || "";
    const footer = FOOTER.exec(description);
    const notes = description.replace(FOOTER, "").trim();
    const deps = parseDeps(todo.text)
        .map(rank => linkTo(idByRank.get(rank)))
        .filter(Boolean)
        .map(target => `[[${target}]]`);
    const twin = todo.twin && linkTo(todo.twin.id);
    const type = parsed.type && parsed.type.toLowerCase().replace(/[^\w\-/]+/g, "-");
    const head = frontmatter({
        id: `doit-${todo.id}`,
        aliases: [],
        tags: [...new Set(["doit", ...(type ? [`doit/${type}`] : []), ...parseTags(todo.text)])],
        area: "doit",
        project: list,
        doit_list: list,
        doit_id: todo.id,
        status: status(todo),
        priority: todo.priorities,
        type: parsed.type,
        rank: parsed.rankLabel,
        claude: parsed.claude,
        sequence: isSequenced(todo) ? todo.sequence : undefined,
        due: todo.due_date,
        created: stamp(todo.created_at),
        completed: todo.done ? stamp(todo.completed_at) : undefined,
        updated: footer ? footer[1].trim().replace(/^(\d{4}-\d{2}-\d{2}):?\s+/, "$1T") : undefined,
        deps: deps.length ? deps : undefined,
        twin: twin ? `[[${twin}]]` : undefined,
    });
    const body = [rest.join("\n").trim(), notes].filter(Boolean).join("\n\n");
    return `${head}\n# ${parsed.rankLabel ? `${parsed.rankLabel}. ` : ""}${title}\n${body ? `\n${body}\n` : ""}`;
}

function renderNote(list, note) {
    const head = frontmatter({
        id: `doit-note-${note.id}`,
        aliases: [],
        tags: ["doit", "doit/note"],
        area: "doit",
        project: list,
        doit_list: list,
        doit_note_id: note.id,
        created: stamp(note.created_at),
        updated: stamp(note.updated_at),
    });
    const body = (note.body || "").trim();
    return `${head}\n# ${note.title || "note"}\n${body ? `\n${body}\n` : ""}`;
}

function renderList(name, data, items, notes, root) {
    const line = ({ todo, parsed, rel }) => {
        const title = `${parsed.rankLabel ? `${parsed.rankLabel}. ` : ""}${label(parsed.body.split("\n")[0])}`;
        const flags = [parsed.type, PRIORITY_LABELS[todo.priorities], todo.due_date && `due ${todo.due_date}`];
        return [`- [[${root}/${rel}|${title}]]`, ...flags.filter(Boolean)].join(" · ");
    };
    const by = s => items.filter(i => status(i.todo) === s);
    const doing = by("in_progress");
    const pending = by("pending").sort(pendingOrder);
    const done = by("done").sort((a, b) => (b.todo.completed_at || 0) - (a.todo.completed_at || 0));
    const sections = [
        ["In progress", doing.map(line)],
        ["Pending", pending.map(line)],
        ["Done", done.map(line)],
        ["Notes", notes.map(({ entry, rel }) => `- [[${root}/${rel}|${label(entry.title || "note")}]]`)],
    ].filter(([, lines]) => lines.length);
    const head = frontmatter({
        id: `doit-list-${name}`,
        aliases: [],
        tags: ["doit", "doit/list"],
        area: "doit",
        project: name,
        doit_list: name,
        in_progress: doing.length,
        pending: pending.length,
        done: done.length,
        updated: stamp(data._metadata && data._metadata.updated_at),
    });
    const body = sections.map(([title, lines]) => `## ${title}\n\n${lines.join("\n")}\n`).join("\n");
    return { counts: [doing.length, pending.length, done.length], text: `${head}\n# ${name}\n${body ? `\n${body}` : ""}` };
}

// files keyed by path relative to the export dir; links are vault paths under `root`
export function buildVault(lists, root) {
    const files = new Map();
    const where = new Map();
    const placed = lists.map(({ name, data }) => {
        const items = place(
            name,
            data.todos || [],
            todo => [parseTodoText(todo.text).rankLabel, slugify(normalizeTodoText(todo.text))].filter(Boolean).join("-"),
            todo => (todo.done ? "done/" : ""),
        ).map(({ entry, rel }) => ({ todo: entry, parsed: parseTodoText(entry.text), rel }));
        for (const item of items) where.set(item.todo.id, `${root}/${item.rel}`);
        const notes = place(name, data.notes || [], note => slugify(note.title || ""), () => "notes/");
        return { name, data, items, notes };
    });
    const rows = [];
    for (const { name, data, items, notes } of placed) {
        const idByRank = new Map(items.filter(i => i.parsed.rankLabel).map(i => [i.parsed.rankLabel, i.todo.id]));
        for (const item of items) files.set(`${item.rel}.md`, renderItem(name, item, id => where.get(id), idByRank));
        for (const { entry, rel } of notes) files.set(`${rel}.md`, renderNote(name, entry));
        const { counts, text } = renderList(name, data, items, notes, root);
        files.set(`${name}/${name}.md`, text);
        rows.push(`| [[${root}/${name}/${name}\\|${name}]] | ${counts.join(" | ")} |`);
    }
    const head = frontmatter({ id: root, aliases: [], tags: ["doit"], area: "doit" });
    const table = ["| list | in progress | pending | done |", "| --- | --- | --- | --- |", ...rows].join("\n");
    files.set(`${root}.md`, `${head}\n# doit todos\n\n${table}\n`);
    return files;
}

function readOrNull(file) {
    try {
        return fs.readFileSync(file, "utf-8");
    } catch {
        return null;
    }
}

// returns whether anything under `dir` was removed, so only dirs this export emptied get rmdir'd
function prune(outDir, dir, files, keep) {
    let removed = false;
    for (const entry of fs.readdirSync(path.join(outDir, dir), { withFileTypes: true })) {
        const rel = dir ? `${dir}/${entry.name}` : entry.name;
        const abs = path.join(outDir, rel);
        if (entry.isDirectory()) {
            if (keep.has(rel) || !prune(outDir, rel, files, keep)) continue;
            removed = true;
            if (!fs.readdirSync(abs).length) fs.rmdirSync(abs);
        } else if (rel.endsWith(".md") && !files.has(rel) && GENERATED.test(readOrNull(abs) || "")) {
            fs.unlinkSync(abs);
            removed = true;
        }
    }
    return removed;
}

// `keep` holds list dirs whose JSON failed to parse; their notes stay until a good read
export function syncDir(outDir, files, keep = new Set()) {
    for (const [rel, content] of files) {
        const abs = path.join(outDir, rel);
        if (readOrNull(abs) === content) continue;
        fs.mkdirSync(path.dirname(abs), { recursive: true });
        fs.writeFileSync(abs, content);
    }
    prune(outDir, "", files, keep);
}

export function exportOnce(outDir) {
    const lists = [];
    const broken = new Set();
    for (const file of fs.readdirSync(LISTS_DIR).filter(f => f.endsWith(".json")).sort()) {
        const name = file.slice(0, -".json".length);
        try {
            lists.push({ name, data: JSON.parse(fs.readFileSync(path.join(LISTS_DIR, file), "utf-8")) });
        } catch (err) {
            broken.add(name);
            console.error(`skip ${file}: ${err.message}`);
        }
    }
    syncDir(outDir, buildVault(lists, path.basename(outDir)), broken);
}

// nvim writes lists in place and MCP/tmux rename over them; fs.watch sees both, and the
// debounce folds a save burst (tmp write, rename, twin write) into one export
function watch(outDir) {
    const run = () => {
        try {
            exportOnce(outDir);
        } catch (err) {
            console.error(err.stack);
        }
    };
    run();
    let timer;
    fs.watch(LISTS_DIR, () => {
        clearTimeout(timer);
        timer = setTimeout(run, 300);
    });
}

function install(outDir) {
    const xml = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
    const plist = path.join(process.env.HOME, "Library/LaunchAgents", `${AGENT_LABEL}.plist`);
    const log = path.join(DATA_DIR, "vault-export.log");
    const args = [process.execPath, fileURLToPath(import.meta.url), outDir, "--watch"];
    fs.writeFileSync(
        plist,
        `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
${args.map(a => `        <string>${xml(a)}</string>`).join("\n")}
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DOIT_DATA_DIR</key>
        <string>${xml(DATA_DIR)}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>${xml(log)}</string>
    <key>StandardErrorPath</key>
    <string>${xml(log)}</string>
</dict>
</plist>
`,
    );
    const domain = `gui/${process.getuid()}`;
    try {
        execFileSync("launchctl", ["bootout", `${domain}/${AGENT_LABEL}`], { stdio: "ignore" });
    } catch {
        // not loaded yet
    }
    execFileSync("launchctl", ["bootstrap", domain, plist]);
    console.log(`installed ${plist}\nlog: ${log}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    const [outArg, mode] = process.argv.slice(2);
    if (!outArg || (mode && mode !== "--watch" && mode !== "--install")) {
        console.error(USAGE);
        process.exit(1);
    }
    const outDir = path.resolve(outArg.replace(/^~(?=\/|$)/, process.env.HOME));
    if (mode === "--install") install(outDir);
    else if (mode === "--watch") watch(outDir);
    else exportOnce(outDir);
}
