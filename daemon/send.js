// Test event sender: node send.js <type> [agent] [tool] [task]
// e.g.  node send.js task.started claude "" t1
//       node send.js task.progress claude Edit t1
//       node send.js perm.requested rin
const [type = "task.progress", agent = "claude", tool, task] = process.argv.slice(2);
const body = JSON.stringify({
  type, agent,
  ...(tool ? { tool } : {}),
  ...(task ? { task } : {}),
});

fetch("http://127.0.0.1:8787/event", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body,
})
  .then((r) => console.log("sent", body, "->", r.status))
  .catch((e) => console.error("daemon not running?", e.message));
