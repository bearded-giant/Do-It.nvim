// switch_list links the tmux WINDOW the server runs in: the window's
// @doit-window-list option (follows renames and moves) plus a copy in
// session.json keyed "<session>:<window>" for after a tmux restart. Worktree
// windows in one session each keep their own list. A real tmux server on a
// private socket plays the user's.
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "doit-mcp-"));
const listsDir = path.join(dataDir, "lists");
fs.mkdirSync(listsDir);

const sock = `/tmp/doit-mcp-${process.pid}.sock`;
const T = (...args) => execFileSync("tmux", ["-S", sock, ...args], { encoding: "utf-8" }).trim();
T("-f", "/dev/null", "new-session", "-d", "-s", "sess", "-n", "tmux config", "-x", "80", "-y", "24");
T("new-window", "-d", "-t", "sess:", "-n", "other");
const live = win => T("display", "-p", "-t", win, "#{@doit-window-list}");

const sessionFile = path.join(dataDir, "session.json");
fs.writeFileSync(sessionFile, JSON.stringify({ active_list: "daily", sessions: { "sess:other": "daily" } }));
for (const name of ["daily", "proj", "spare"]) {
    fs.writeFileSync(path.join(listsDir, `${name}.json`), JSON.stringify({ todos: [], _metadata: {} }));
}

const server = spawn("node", [path.join(here, "server.js")], {
    env: {
        ...process.env,
        DOIT_DATA_DIR: dataDir,
        DOIT_ACTIVE_LIST: "",
        TMUX: `${sock},${T("display", "-p", "#{pid}")},0`,
        TMUX_PANE: T("display", "-p", "-t", "sess:tmux config", "#{pane_id}"),
    },
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

const readSession = () => JSON.parse(fs.readFileSync(sessionFile, "utf-8"));

try {
    await request("initialize", {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "test", version: "0" },
    });
    server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

    // default scope links this window, live and persisted, and leaves the session's other windows alone
    assert.match(await callTool("switch_list", { list: "proj" }), /linked tmux window "sess:tmux config"/);
    assert.deepEqual(readSession().sessions, { "sess:other": "daily", "sess:tmux config": "proj" });
    assert.equal(live("sess:tmux config"), "proj");
    assert.equal(live("sess:other"), "");

    // scope=window writes only the link, not the global pointer
    await callTool("switch_list", { list: "spare", scope: "window" });
    assert.equal(readSession().sessions["sess:tmux config"], "spare");
    assert.equal(readSession().active_list, "proj");

    // scope=session, the older name, still means this window
    await callTool("switch_list", { list: "proj", scope: "session" });
    assert.equal(live("sess:tmux config"), "proj");
    assert.equal(readSession().active_list, "proj");

    // list_lists names the linking windows
    assert.match(await callTool("list_lists", {}), /proj \[claude\]: .*\(linked: sess:tmux config\)/);

    // a list rename carries the live link and its persisted copy
    await callTool("rename_list", { old_name: "proj", new_name: "proj2" });
    assert.equal(live("sess:tmux config"), "proj2");
    assert.equal(readSession().sessions["sess:tmux config"], "proj2");

    // a list delete drops the live link and its persisted copy
    await callTool("delete_list", { name: "proj2" });
    assert.equal(live("sess:tmux config"), "");
    assert.equal(readSession().sessions["sess:tmux config"], undefined);
} finally {
    server.kill();
    T("kill-server");
    fs.rmSync(sock, { force: true });
    fs.rmSync(dataDir, { recursive: true, force: true });
}
console.log("switch_list window links: ok");
