// An owed item is two files' worth of state, so every tool that changes one
// twin has to be checked against the other file on disk.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "doit-mcp-"));
const listsDir = path.join(dataDir, "lists");
fs.mkdirSync(listsDir);

fs.writeFileSync(path.join(dataDir, "session.json"), JSON.stringify({ active_list: "daily" }));
fs.writeFileSync(path.join(listsDir, "daily.json"), JSON.stringify({
    todos: [{ id: "daily_1", text: "[chore] 1. water plants", done: false, order_index: 1 }],
    _metadata: {},
}));
fs.writeFileSync(path.join(listsDir, "proj.json"), JSON.stringify({
    todos: [{ id: "proj_1", text: "claude: [bug] 1. fix the thing", done: false, order_index: 1 }],
    _metadata: {},
}));
fs.writeFileSync(path.join(listsDir, "other.json"), JSON.stringify({ todos: [], _metadata: {} }));

const server = spawn("node", [path.join(here, "server.js")], {
    env: { ...process.env, DOIT_DATA_DIR: dataDir, DOIT_ACTIVE_LIST: "", TMUX: "" },
    stdio: ["pipe", "pipe", "inherit"],
});

let buffer = "";
const pending = new Map();
server.stdout.on("data", chunk => {
    buffer += chunk;
    let nl;
    while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line) continue;
        const msg = JSON.parse(line);
        const resolve = pending.get(msg.id);
        if (resolve) {
            pending.delete(msg.id);
            resolve(msg);
        }
    }
});

let nextId = 1;
function request(method, params) {
    const id = nextId++;
    return new Promise(resolve => {
        pending.set(id, resolve);
        server.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
}

async function callTool(name, args) {
    const res = await request("tools/call", { name, arguments: args });
    assert.ok(res.result, `${name} returned no result: ${JSON.stringify(res)}`);
    return res.result.content.map(c => c.text).join("\n");
}

const read = name => JSON.parse(fs.readFileSync(path.join(listsDir, `${name}.json`), "utf-8"));
const byText = (name, needle) => read(name).todos.find(t => t.text.includes(needle));

await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "test", version: "0" },
});
server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

// owe writes the project item and its daily twin, each naming the other
const added = await callTool("add_todo", {
    list: "proj",
    text: "confirm callback on stage",
    type: "gate",
    deps: [1],
    priority: "urgent",
    due: "2030-01-02",
    owe: true,
    description: "do:\nlog in on stage",
});
assert.match(added, /Added to "proj": \[gate\] 2\. owed in daily #2: confirm callback on stage \(dep on #1\)/);
assert.match(added, /Twin in "daily": \[gate\] 2\. proj: confirm callback on stage \[id:/);

let p = byText("proj", "owed in daily");
let d = byText("daily", "proj: confirm");
assert.deepEqual(p.twin, { list: "daily", id: d.id });
assert.deepEqual(d.twin, { list: "proj", id: p.id });
assert.ok(p.description.startsWith(`daily: ${d.id}\n\ndo:\nlog in on stage`));
assert.ok(d.description.startsWith(`from: proj #2 (id ${p.id})\n\ndo:\nlog in on stage`));
assert.equal(d.priorities, "urgent");
assert.equal(d.due_date, "2030-01-02");
assert.ok(!d.text.includes("dep on"), "project deps are meaningless in daily");

// claude: work cannot be owed
const rejected = await callTool("add_todo", { list: "proj", text: "claude: do it", owe: true }).catch(e => String(e));
assert.match(String(rejected), /drop the leading 'claude:'/);

// owe on daily itself is a plain daily item
await callTool("add_todo", { list: "daily", text: "buy milk", owe: true });
assert.equal(byText("daily", "buy milk").twin, undefined);

// complete and revert follow across files
assert.match(await callTool("complete_todo", { id: d.id }), /Twin in "proj" completed/);
assert.equal(byText("proj", "owed in daily").done, true);
await callTool("revert_todo", { id: p.id });
assert.equal(byText("daily", "proj: confirm").done, false);

// update_todo mirrors done / priority / due, not text
await callTool("update_todo", { id: p.id, priority: "none", due: "" });
d = byText("daily", "proj: confirm");
assert.equal(d.priorities, undefined);
assert.equal(d.due_date, undefined);
await callTool("update_todo", { id: p.id, done: true });
assert.equal(byText("daily", "proj: confirm").done, true);
await callTool("update_todo", { id: p.id, done: false });

// move keeps the link, rename follows the file
assert.match(await callTool("move_todo", { id: p.id, to_list: "other" }), /relinked/);
assert.deepEqual(byText("daily", "proj: confirm").twin, { list: "other", id: p.id });
await callTool("rename_list", { old_name: "other", new_name: "renamed" });
assert.deepEqual(byText("daily", "proj: confirm").twin, { list: "renamed", id: p.id });

// delete takes the twin with it, undo-able on both sides
assert.match(await callTool("delete_todo", { id: p.id }), /Twin in "daily" deleted/);
assert.equal(byText("daily", "proj: confirm"), undefined);
assert.equal(read("daily")._metadata.deleted_todos[0].id, d.id);

// a twin that is already gone is reported, not thrown
const lone = await callTool("add_todo", { list: "proj", text: "ping sam", type: "ping", owe: true });
const loneDaily = byText("daily", "proj: ping sam");
await callTool("complete_todo", { id: loneDaily.id, list: "daily" });
const daily = read("daily");
daily.todos = daily.todos.filter(t => t.id !== loneDaily.id);
fs.writeFileSync(path.join(listsDir, "daily.json"), JSON.stringify(daily));
assert.equal(byText("proj", "ping sam").done, true);
assert.match(await callTool("revert_todo", { id: byText("proj", "ping sam").id }), /no longer in "daily"/);
assert.match(lone, /owed in daily #\d+: ping sam/);

// tmux links and the global pointer are the user's view state; an omitted list goes to daily
fs.writeFileSync(path.join(dataDir, "session.json"), JSON.stringify({ active_list: "proj", sessions: { work: "proj" } }));
assert.match(await callTool("add_todo", { text: "no list given" }), /Added to "daily"/);

server.kill();
fs.rmSync(dataDir, { recursive: true, force: true });
console.log("owe twins: ok");
