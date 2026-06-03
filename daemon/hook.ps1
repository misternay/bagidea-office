# Claude Code hook → office daemon forwarder.
# Wired in .claude/settings.json. Reads the hook payload from stdin, maps it to
# an office event, and POSTs to the daemon. Must NEVER block or fail the hook:
# best-effort with a short timeout, always exits 0.
param([string]$Type = "task.progress")

# Sessions spawned by the office adapter report through stream-json instead —
# skip the hook to avoid double events.
if ($env:OFFICE_ADAPTER -eq "1") { exit 0 }

try {
    $payload = @{ type = $Type; agent = "claude" }
    $stdin = [Console]::In.ReadToEnd()
    if ($stdin) {
        $h = $stdin | ConvertFrom-Json
        if ($h.tool_name) { $payload.tool = $h.tool_name }
        if ($h.session_id) { $payload.task = "s" + $h.session_id.Substring(0, 6) }
    }
    Invoke-RestMethod -Uri "http://127.0.0.1:8787/event" -Method Post `
        -Body ($payload | ConvertTo-Json -Compress) -ContentType "application/json" `
        -TimeoutSec 2 | Out-Null
} catch {}
exit 0
