// A list note may link to todos on its list via todo_ids. Ranks resolve to ids
// on write, and a link whose todo is gone is skipped on read, never an error.
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
fs.writeFileSync(path.join(listsDir, "daily.json"), JSON.stringify({ todos: [], _metadata: {} }));
fs.writeFileSync(path.join(listsDir, "work.json"), JSON.stringify({
    todos: [
        { id: "w3", text: "claude: [bug] 3. fix the thing", done: false, order_index: 1 },
        { id: "w5", text: "claude: [chore] 5. tidy docs", done: false, order_index: 2 },
        { id: "w9", text: "typed by hand", done: false, order_index: 3 },
    ],
    notes: [
        { id: "n_old", title: "legacy", body: "no links field", created_at: 1, updated_at: 1 },
    ],
    _metadata: {},
}));

const server = spawn("node", [path.join(here, "server.js")], {
    env: { ...process.env, DOIT_DATA_DIR: dataDir, DOIT_ACTIVE_LIST: "" },
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

const readWork = () => JSON.parse(fs.readFileSync(path.join(listsDir, "work.json"), "utf-8"));
const noteByTitle = title => readWork().notes.find(n => n.title === title);

await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "test", version: "0" },
});
server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

// create resolves a rank and an id (mixed), stored as ids
const created = await callTool("create_note", { list: "work", title: "plan", body: "b", todo_ids: [3, "w9"] });
assert.match(created, /todos: #3 fix the thing, typed by hand \[id:w9\]/);
assert.deepEqual(noteByTitle("plan").todo_ids, ["w3", "w9"]);

// a string rank and a #-prefixed rank resolve too; duplicates collapse
await callTool("create_note", { list: "work", title: "dupes", todo_ids: ["5", "#5", "w5"] });
assert.deepEqual(noteByTitle("dupes").todo_ids, ["w5"]);

// an unknown ref is rejected and nothing is written
const before = readWork().notes.length;
const bad = await callTool("create_note", { list: "work", title: "bad", todo_ids: [3, 42] });
assert.match(bad, /Todo "42" not found in list "work"/);
assert.equal(readWork().notes.length, before);

// a note created without todo_ids carries no field
await callTool("create_note", { list: "work", title: "plain" });
assert.equal("todo_ids" in noteByTitle("plain"), false);

// update replaces the set
const planId = noteByTitle("plan").id;
const updated = await callTool("update_note", { list: "work", id: planId, todo_ids: [5] });
assert.match(updated, /todos: #5 tidy docs/);
assert.deepEqual(noteByTitle("plan").todo_ids, ["w5"]);

// update without todo_ids leaves links alone
await callTool("update_note", { list: "work", id: planId, body: "new body" });
assert.deepEqual(noteByTitle("plan").todo_ids, ["w5"]);

// update with an unknown ref keeps the old links
assert.match(await callTool("update_note", { list: "work", id: planId, todo_ids: ["nope"] }), /Todo "nope" not found/);
assert.deepEqual(noteByTitle("plan").todo_ids, ["w5"]);

// [] clears
await callTool("update_note", { list: "work", id: planId, todo_ids: [] });
assert.equal("todo_ids" in noteByTitle("plan"), false);

// stale ids (deleted/moved todos) are skipped on read, never an error
const work = readWork();
work.notes.push({ id: "n_stale", title: "stale", body: "x", todo_ids: ["gone", "w3"], created_at: 1, updated_at: 1 });
work.notes.push({ id: "n_dead", title: "dead", body: "x", todo_ids: ["gone"], created_at: 1, updated_at: 1 });
fs.writeFileSync(path.join(listsDir, "work.json"), JSON.stringify(work));

const listed = await callTool("list_notes", { list: "work" });
assert.match(listed, /- stale {2}\[id:n_stale\]\n {4}todos: #3 fix the thing\n/);
assert.match(listed, /- dead {2}\[id:n_dead\]$/);
assert.match(listed, /- legacy {2}\[id:n_old\]\n- /);
assert.doesNotMatch(listed, /gone/);

const got = await callTool("get_note", { list: "work", id: "n_stale" });
assert.equal(got, "# stale  [id:n_stale]\ntodos: #3 fix the thing\n\nx");
assert.equal(await callTool("get_note", { list: "work", id: "n_dead" }), "# dead  [id:n_dead]\n\nx");

// get_todo lists the notes that link to the item
const todo = await callTool("get_todo", { id: "w3" });
assert.match(todo, /List notes \(1\):\n {2}stale {2}\[id:n_stale\]/);
assert.doesNotMatch(await callTool("get_todo", { id: "w9" }), /List notes/);

server.kill();
fs.rmSync(dataDir, { recursive: true, force: true });
console.log("note todo_ids links: ok");
