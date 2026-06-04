// Test event sender: node send.js <type> [agent] [tool] [task]
// e.g.  node send.js task.started claude "" t1
//       node send.js task.progress claude Edit t1
//       node send.js collab.started rin,dev,mira "" t9   (comma = multi-agent)
const [type = "task.progress", agent = "claude", tool, task, text] = process.argv.slice(2);
const multi = agent.includes(",");
const body = JSON.stringify({
  type,
  ...(multi ? { agents: agent.split(",") } : { agent }),
  ...(tool ? { tool } : {}),
  ...(task ? { task } : {}),
  ...(text ? { text } : {}),
});

fetch("http://127.0.0.1:8787/event", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body,
})
  .then((r) => console.log("sent", body, "->", r.status))
  .catch((e) => console.error("daemon not running?", e.message));
