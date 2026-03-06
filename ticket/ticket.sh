#!/usr/bin/env bash
# ticket.sh — open Claude ready to analyse a pasted image and create a Linear ticket
#
# INSTALL:
#   chmod +x ticket.sh
#   sudo ln -sf "$(pwd)/ticket.sh" /usr/local/bin/ticket
#
# BIND to calculator key:
#   Use Karabiner-Elements or BetterTouchTool to map the calculator key
#   to run: /usr/local/bin/ticket

set -euo pipefail

PROJECT_DIR="$HOME/v7/sales-proposal-building-tool"

PROMPT="Analyse the image I will paste. Based on what you see, create a Linear ticket in the current cycle of this team 6ab45a79-6ebe-4c67-9f33-b3e0c365815a. Include a clear title, a description of the issue or feature visible in the screenshot, and suggest acceptance criteria. You have all the access you need to create the ticket. Use all the tools at your disposal to create the ticket and fetch any relevant information from the repo or fireflies using MCP. Upload the screenshot to Linear as an image in the description of the ticket. Before creating the ticket, ask the user if they want to add any additional information to the ticket. If they do, ask them for the information and add it to the ticket."

osascript <<EOF
tell application "iTerm"
  activate
  set newWindow to (create window with default profile)
  tell current session of newWindow
    write text "cd ${PROJECT_DIR} && claude --dangerously-skip-permissions --system-prompt '${PROMPT}'"
  end tell
end tell
EOF
