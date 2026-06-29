#!/bin/bash
# macOS project window manager — mirrors winproj.ps1 via AppleScript.
# Terminal.app tabs are identified by their custom title BAGIDEA_PROJ_<id>
# (set in server.js launch when the tab is created via osascript).
#
# Actions: sweep | show <id> | hide <id> | stop <id>
#
# sweep  — output "<id> 0|1" for every Terminal tab whose custom title
#          starts with BAGIDEA_PROJ_. 1 = visible (not minimised).
# show   — de-minimise and bring the matching Terminal window to front.
# hide   — minimise the matching Terminal window.
# stop   — exit every shell in the matching tab, close it.
#
# (killdir is handled inline in server.js via lsof for macOS+Linux —
#  no need to round-trip through this script.)

ACTION="${1:-sweep}"
ID="${2:-}"

# ── Terminal window/tab operations ─────────────────────────────────────
osascript <<APPLESCRIPT
on run
  set theAction to "$ACTION"
  set theId to "$ID"
  set output to ""

  tell application "Terminal"
    -- Walk every window, every tab.
    -- Match on the custom title we set at launch (BAGIDEA_PROJ_<id>).
    set winCount to count of windows
    repeat with i from 1 to winCount
      set w to window i
      repeat with t in tabs of w
        set ct to custom title of t
        if ct starts with "BAGIDEA_PROJ_" then
          -- Extract the project id after the prefix. "BAGIDEA_PROJ_" is 13
          -- chars, so the id begins at index 14. Keep these in sync if the
          -- marker in server.js (macOS launch branch) ever changes.
          set projId to text 14 thru -1 of ct

          if theAction is "sweep" then
            set isMin to miniaturized of w
            if isMin then
              set output to output & projId & " 0" & linefeed
            else
              set output to output & projId & " 1" & linefeed
            end if

          else if projId is theId then
            if theAction is "hide" then
              set miniaturized of w to true

            else if theAction is "show" then
              set miniaturized of w to false
              set index of w to 1
              activate

            else if theAction is "stop" then
              -- Graceful: send exit to the tab's shell, then close.
              -- Terminal.app auto-closes the window when its last tab goes.
              try
                do script "exit" in t
              end try
              delay 0.3
              try
                close t
              end try
            end if
          end if
        end if
      end repeat
    end repeat
  end tell

  return output
end run
APPLESCRIPT
