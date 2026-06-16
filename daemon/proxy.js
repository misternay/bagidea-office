"use strict";
// ---------------------------------------------------------------------------
// Built-in Anthropic ↔ OpenAI translation proxy (zero-dep, Node global fetch).
//
// Lets OpenAI/Gemini back an agent WITHOUT running LiteLLM: the daemon exposes
//   POST /proxy/openai/v1/messages   and   /proxy/gemini/v1/messages
// `claude` (with ANTHROPIC_BASE_URL → one of those) sends Anthropic Messages API
// requests here; we translate to OpenAI Chat Completions, call the upstream with
// the user's existing main key (reg.apiKeys.OPENAI_API_KEY / GEMINI_API_KEY),
// and translate the reply back — streaming (SSE) + tool-use included.
//
// Gemini is reached via Google's OpenAI-compatible endpoint, so ONE translator
// serves both. The real key never reaches the sandbox; it's injected here.
// ---------------------------------------------------------------------------

const UPSTREAM = {
  openai: { url: "https://api.openai.com/v1/chat/completions", key: "OPENAI_API_KEY",
            fallbackModel: "gpt-4o-mini" },
  gemini: { url: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            key: "GEMINI_API_KEY", fallbackModel: "gemini-2.5-flash" },
  openrouter: { url: "https://openrouter.ai/api/v1/chat/completions", fallbackModel: "" },
  nvidia: { url: "https://integrate.api.nvidia.com/v1/chat/completions", fallbackModel: "" },
};

// Resolve the OpenAI-compatible upstream for a provider. An explicit
// reg.providerConfig[provider].baseUrl (a `/v1`-style base — used by OpenRouter,
// NVIDIA, and any custom provider) wins; otherwise the built-in default URL.
// Key: providerConfig.token first, else the built-in main-key env (openai/gemini).
function upstreamFor(provider, reg) {
  const pc = (reg.providerConfig || {})[provider] || {};
  const up = UPSTREAM[provider] || {};
  const chat = pc.baseUrl ? pc.baseUrl.replace(/\/+$/, "") + "/chat/completions" : up.url;
  const key = pc.token || (up.key && (reg.apiKeys || {})[up.key]) || "";
  const models = chat ? chat.replace(/\/chat\/completions$/, "/models") : "";
  return { chat, models, key, fallbackModel: pc.model || up.fallbackModel || "" };
}

const STOP = { stop: "end_turn", length: "max_tokens", tool_calls: "tool_use", content_filter: "end_turn" };

// --- Anthropic request → OpenAI Chat Completions request (pure, testable) ----
function toOpenAI(a, model) {
  const msgs = [];
  if (a.system) {
    const sys = typeof a.system === "string"
      ? a.system
      : a.system.map((b) => (b && b.text) || "").join("\n");
    if (sys) msgs.push({ role: "system", content: sys });
  }
  for (const m of a.messages || []) {
    if (typeof m.content === "string") { msgs.push({ role: m.role, content: m.content }); continue; }
    const parts = [], toolCalls = [], toolResults = [];
    for (const b of m.content || []) {
      if (b.type === "text") parts.push({ type: "text", text: b.text || "" });
      else if (b.type === "image" && b.source) {
        const s = b.source;
        const url = s.type === "base64" ? `data:${s.media_type};base64,${s.data}` : s.url;
        if (url) parts.push({ type: "image_url", image_url: { url } });
      } else if (b.type === "tool_use") {
        toolCalls.push({ id: b.id, type: "function",
          function: { name: b.name, arguments: JSON.stringify(b.input || {}) } });
      } else if (b.type === "tool_result") {
        let c = b.content;
        if (Array.isArray(c)) c = c.map((x) => (x && x.type === "text" ? x.text : JSON.stringify(x))).join("\n");
        else if (typeof c !== "string") c = JSON.stringify(c == null ? "" : c);
        toolResults.push({ role: "tool", tool_call_id: b.tool_use_id, content: c || "" });
      }
    }
    if (m.role === "user") {
      for (const tr of toolResults) msgs.push(tr);          // tool replies first
      if (parts.length) {
        const onlyText = parts.every((p) => p.type === "text");
        msgs.push({ role: "user", content: onlyText ? parts.map((p) => p.text).join("\n") : parts });
      }
    } else {
      const am = { role: "assistant" };
      const txt = parts.filter((p) => p.type === "text").map((p) => p.text).join("");
      if (txt) am.content = txt;
      if (toolCalls.length) am.tool_calls = toolCalls;
      if (!am.content && !am.tool_calls) am.content = "";
      msgs.push(am);
    }
  }
  const out = { model, messages: msgs, stream: !!a.stream };
  if (a.max_tokens) out.max_tokens = a.max_tokens;
  if (a.stream) out.stream_options = { include_usage: true };
  if (Array.isArray(a.tools) && a.tools.length) {
    out.tools = a.tools
      .filter((t) => t && t.name && t.input_schema)
      .map((t) => ({ type: "function",
        function: { name: t.name, description: t.description || "", parameters: t.input_schema } }));
    const tc = a.tool_choice;
    if (tc && tc.type === "auto") out.tool_choice = "auto";
    else if (tc && tc.type === "any") out.tool_choice = "required";
    else if (tc && tc.type === "tool" && tc.name) out.tool_choice = { type: "function", function: { name: tc.name } };
  }
  return out;
}

// --- OpenAI non-streaming response → Anthropic message (pure, testable) ------
function toAnthropic(o, model) {
  const choice = (o.choices || [])[0] || {};
  const msg = choice.message || {};
  const content = [];
  if (msg.content) content.push({ type: "text", text: msg.content });
  for (const tc of msg.tool_calls || []) {
    let input = {};
    try { input = JSON.parse((tc.function && tc.function.arguments) || "{}"); } catch {}
    content.push({ type: "tool_use", id: tc.id, name: tc.function && tc.function.name, input });
  }
  return {
    id: o.id || "msg_proxy", type: "message", role: "assistant", model, content,
    stop_reason: STOP[choice.finish_reason] || "end_turn", stop_sequence: null,
    usage: { input_tokens: (o.usage || {}).prompt_tokens || 0,
             output_tokens: (o.usage || {}).completion_tokens || 0 },
  };
}

function sse(res, event, data) { res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`); }

// Resolve the model to forward: ignore claude-* (means --model didn't apply) and
// blanks, falling back to a safe widely-available model per upstream.
function pickModel(reqModel, fallback) {
  const m = String(reqModel || "");
  return (!m || /^claude/i.test(m)) ? (fallback || m) : m;
}

async function handle(req, res, provider, reg, raw) {
  const { chat, key, fallbackModel } = upstreamFor(provider, reg);
  if (!chat) {
    res.writeHead(404, { "content-type": "application/json" });
    return res.end(JSON.stringify({ type: "error",
      error: { type: "not_found_error", message: `no endpoint configured for provider "${provider}"` } }));
  }
  if (!key) {
    res.writeHead(400, { "content-type": "application/json" });
    return res.end(JSON.stringify({ type: "error",
      error: { type: "authentication_error", message: `key not set for "${provider}" — add it in ⚙ CONNECT` } }));
  }
  let a;
  try { a = JSON.parse(raw); } catch { res.writeHead(400); return res.end("bad json"); }
  const model = pickModel(a.model, fallbackModel);
  const body = toOpenAI(a, model);

  // Abort the upstream ONLY if the client (claude) drops before we've finished —
  // detected via res 'close' while the response hasn't ended. (Do NOT use req
  // 'close': it fires the moment the request body is read, which is before/while
  // the upstream fetch runs, and would abort every healthy request → 502.)
  const ac = new AbortController();
  res.on("close", () => { if (!res.writableEnded) { try { ac.abort(); } catch {} } });

  let r;
  try {
    r = await fetch(chat, { method: "POST", signal: ac.signal,
      headers: { "content-type": "application/json", authorization: "Bearer " + key },
      body: JSON.stringify(body) });
  } catch (e) {
    res.writeHead(502, { "content-type": "application/json" });
    return res.end(JSON.stringify({ type: "error",
      error: { type: "api_error", message: "upstream fetch failed: " + e.message } }));
  }

  if (!r.ok) {
    const txt = await r.text().catch(() => "");
    res.writeHead(r.status, { "content-type": "application/json" });
    return res.end(JSON.stringify({ type: "error",
      error: { type: "api_error", message: (txt || `upstream ${r.status}`).slice(0, 600) } }));
  }

  if (!body.stream) {
    const j = await r.json();
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify(toAnthropic(j, model)));
  }

  // --- streaming: OpenAI SSE deltas → Anthropic SSE events ---
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
  let started = false, idx = -1, mode = null;        // mode: "text" | "tool" | null
  const toolIdx = {};                                // openai tool index → anthropic block idx
  let usage = { input_tokens: 0, output_tokens: 0 }, stop = "end_turn";
  const start = () => { if (!started) { started = true;
    sse(res, "message_start", { type: "message_start", message: { id: "msg_proxy", type: "message",
      role: "assistant", model, content: [], stop_reason: null, stop_sequence: null, usage } }); } };
  const closeBlock = () => { if (mode) { sse(res, "content_block_stop", { type: "content_block_stop", index: idx }); mode = null; } };

  let buf = "";
  try {
    for await (const chunk of r.body) {
      buf += Buffer.from(chunk).toString("utf8");
      let nl;
      while ((nl = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, nl).trim(); buf = buf.slice(nl + 1);
        if (!line.startsWith("data:")) continue;
        const p = line.slice(5).trim();
        if (p === "[DONE]") continue;
        let j; try { j = JSON.parse(p); } catch { continue; }
        if (j.usage) usage = { input_tokens: j.usage.prompt_tokens || 0, output_tokens: j.usage.completion_tokens || 0 };
        const ch = (j.choices || [])[0]; if (!ch) continue;
        const d = ch.delta || {};
        start();
        if (d.content) {
          if (mode !== "text") { closeBlock(); idx++; mode = "text";
            sse(res, "content_block_start", { type: "content_block_start", index: idx, content_block: { type: "text", text: "" } }); }
          sse(res, "content_block_delta", { type: "content_block_delta", index: idx, delta: { type: "text_delta", text: d.content } });
        }
        for (const tc of d.tool_calls || []) {
          const oi = tc.index == null ? 0 : tc.index;
          if (!(oi in toolIdx)) { closeBlock(); idx++; toolIdx[oi] = idx; mode = "tool";
            sse(res, "content_block_start", { type: "content_block_start", index: idx,
              content_block: { type: "tool_use", id: tc.id || ("call_" + idx), name: (tc.function && tc.function.name) || "", input: {} } }); }
          else { mode = "tool"; idx = toolIdx[oi]; }
          const args = tc.function && tc.function.arguments;
          if (args) sse(res, "content_block_delta", { type: "content_block_delta", index: toolIdx[oi], delta: { type: "input_json_delta", partial_json: args } });
        }
        if (ch.finish_reason) stop = STOP[ch.finish_reason] || "end_turn";
      }
    }
  } catch (e) { /* upstream stream dropped — close out cleanly below */ }

  if (!res.writableEnded) {
    try {
      start(); closeBlock();
      sse(res, "message_delta", { type: "message_delta", delta: { stop_reason: stop, stop_sequence: null }, usage: { output_tokens: usage.output_tokens } });
      sse(res, "message_stop", { type: "message_stop" });
      res.end();
    } catch {}
  }
}

module.exports = { handle, toOpenAI, toAnthropic, pickModel, upstreamFor, UPSTREAM };
