// A copied id has to reach the item without a list name — the server is driven
// over stdio here so the resolution runs through the real tool plumbing.
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
    todos: [{ id: "daily_1", text: "on the active list", done: false, order_index: 1 }],
    _metadata: {},
}));
fs.writeFileSync(path.join(listsDir, "work.json"), JSON.stringify({
    todos: [{
        id: "work_7",
        text: "claude: [bug] 3. fix the thing",
        done: false,
        order_index: 1,
        priorities: "critical",
        due_date: "2020-01-01",
        description: "some notes",
    }],
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

await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "test", version: "0" },
});
server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

// get_todo finds an id that is not on the active list
const fetched = await callTool("get_todo", { id: "work_7" });
assert.match(fetched, /List: work/);
assert.match(fetched, /Priority: critical/);
assert.match(fetched, /overdue/);
assert.match(fetched, /fix the thing/);
assert.match(fetched, /some notes/);

// a missing id says so instead of throwing
assert.match(await callTool("get_todo", { id: "nope" }), /No todo with id "nope"/);

// an id-only action writes to the list that holds the id, not the active one
await callTool("start_todo", { id: "work_7" });
const work = JSON.parse(fs.readFileSync(path.join(listsDir, "work.json"), "utf-8"));
assert.equal(work.todos[0].in_progress, true);
const daily = JSON.parse(fs.readFileSync(path.join(listsDir, "daily.json"), "utf-8"));
assert.equal(daily.todos[0].in_progress, undefined);

// an explicit list still wins, so a wrong pairing errors rather than silently retargeting
const wrongList = await callTool("complete_todo", { id: "work_7", list: "daily" }).catch(e => String(e));
assert.match(wrongList, /not found in list "daily"/);

server.kill();
fs.rmSync(dataDir, { recursive: true, force: true });
console.log("get_todo + cross-list id resolution: ok");
