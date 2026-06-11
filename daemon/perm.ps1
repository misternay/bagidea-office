# PreToolUse hook for office-adapter sessions (wired in workspace/.claude/).
# Safe read tools pass through; anything else walks to the Security Center:
# we long-poll the daemon until the user stamps Allow/Deny on the overlay.
try {
    # Read stdin as UTF-8 explicitly. [Console]::In uses the console codepage
    # (cp874/ANSI on Thai Windows) which mangles the UTF-8 JSON Claude Code sends,
    # turning Thai text into mojibake before it ever reaches the overlay.
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $stdin = $reader.ReadToEnd()
    $reader.Close()
    $h = $stdin | ConvertFrom-Json
    $tool = [string]$h.tool_name

    # Safe tools: no opinion, let normal permission flow handle them.
    if ($tool -in @("Read", "Glob", "Grep")) { exit 0 }

    $id = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $agent = $env:OFFICE_AGENT; if (-not $agent) { $agent = "claude" }
    $task = $env:OFFICE_TASK; if (-not $task) { $task = "" }
    $inputJson = ""
    if ($h.tool_input) { $inputJson = ($h.tool_input | ConvertTo-Json -Compress -Depth 4) }

    $body = @{ id = $id; agent = $agent; task = $task; tool = $tool; input = $inputJson } | ConvertTo-Json -Compress
    # Send the body as raw UTF-8 bytes so Thai survives the POST intact.
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $decision = "deny"
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:8787/perm/request" -Method Post `
            -Body $bodyBytes -ContentType "application/json; charset=utf-8" -TimeoutSec 55
        if ($r.decision -eq "allow") { $decision = "allow" }
    } catch {}

    @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = $decision
            permissionDecisionReason = "BagIdea Office Security Center ($decision)"
        }
    } | ConvertTo-Json -Compress -Depth 5
} catch {}
exit 0
