// List source flag and the shared view filter, driven over stdio through the
// real tool plumbing. Unflagged lists count as claude; daily is always mine.
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

const sessionFile = path.join(dataDir, "session.json");
fs.writeFileSync(sessionFile, JSON.stringify({ active_list: "daily", sessions: { "s:w": "proj" } }));
const writeList = (name, metadata, todos = []) =>
    fs.writeFileSync(path.join(listsDir, `${name}.json`), JSON.stringify({ todos, _metadata: metadata }));
writeList("daily", {});
writeList("proj", { created_at: 5 }, [{ id: "p1", text: "keep me", done: false, order_index: 1 }]);
writeList("mine", { source: "user" });
const readList = name => JSON.parse(fs.readFileSync(path.join(listsDir, `${name}.json`), "utf-8"));

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

async function call(name, args) {
    const res = await request("tools/call", { name, arguments: args });
    assert.ok(res.result, `${name} returned no result: ${JSON.stringify(res)}`);
    return { text: res.result.content.map(c => c.text).join("\n"), isError: res.result.isError };
}

await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "test", version: "0" },
});

let r = await call("list_lists", {});
assert.match(r.text, /^daily \[mine\]/m, "daily is mine");
assert.match(r.text, /^proj \[claude\]/m, "unflagged counts as claude");
assert.match(r.text, /^mine \[mine\]/m, "source user is mine");

r = await call("list_lists", { source: "mine" });
assert.doesNotMatch(r.text, /^proj /m, "mine filter drops claude lists");
assert.match(r.text, /^daily /m);

r = await call("list_lists", { source: "claude" });
assert.equal(r.text.split("\n").length, 1, "claude filter shows only proj");
assert.match(r.text, /^proj /m);

r = await call("set_list_source", { name: "proj", source: "user" });
assert.match(r.text, /now mine/);
const proj = readList("proj");
assert.equal(proj._metadata.source, "user");
assert.equal(proj._metadata.created_at, 5, "other metadata survives");
assert.equal(proj.todos[0].text, "keep me", "todos survive");

r = await call("list_lists", { source: "claude" });
assert.equal(r.text, "No claude lists.");

r = await call("set_list_source", { name: "daily", source: "mcp" });
assert.ok(r.isError, "daily cannot become claude's");
assert.equal(readList("daily")._metadata.source, undefined, "daily file untouched");

r = await call("set_list_source", { name: "nope", source: "user" });
assert.ok(r.isError, "missing list errors");

r = await call("set_source_filter", { filter: "mine" });
assert.match(r.text, /mine lists/);
const session = JSON.parse(fs.readFileSync(sessionFile, "utf-8"));
assert.equal(session.source_filter, "mine");
assert.equal(session.sessions["s:w"], "proj", "other session keys survive");

r = await call("list_lists", {});
assert.match(r.text, /^mine /m, "the view filter never narrows what the server lists");
assert.match(r.text, /^proj /m);

r = await call("add_todo", { list: "proj", text: "claude can still write here", type: "chore" });
assert.ok(!r.isError, "any session can use a list whatever its source");

server.kill();
fs.rmSync(dataDir, { recursive: true, force: true });
console.log("list-source: ok");
