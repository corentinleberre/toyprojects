#!/usr/bin/env bash
# dev.sh — tmux workspace bootstrapper
#
# INSTALL (run once):
#   chmod +x dev.sh
#   sudo cp dev.sh /usr/local/bin/dev   # or anywhere on your PATH
#
# USAGE:
#   dev                    # prompts for branch; Enter with no input → current branch
#   dev feature/my-branch  # jump straight to a branch
#   dev kill               # interactive picker to kill a dev session
#   dev kill feature/foo   # kill the session for a specific branch
#   dev kill all           # kill all dev sessions

set -euo pipefail

# ──────────────────────────────────────────────
# CONFIG — override via env vars in your shell profile
# ──────────────────────────────────────────────
WORKTREES_DIR="${WORKTREES_DIR:-$HOME/worktrees}"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)}"
SESSION_PREFIX="dev"

# ──────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────
die()  { echo "❌  $*" >&2; exit 1; }
info() { echo "→  $*" >&2; }

require_git() {
  git rev-parse --git-dir &>/dev/null || die "Not inside a git repository."
}

current_branch() {
  git rev-parse --abbrev-ref HEAD
}

# ──────────────────────────────────────────────
# SPOTIFY STATUS (macOS AppleScript)
# Written once to ~/.local/bin/tmux-spotify and called by tmux status-right
# ──────────────────────────────────────────────
install_timer_script() {
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/tmux-uptime" << 'UPTIME'
#!/usr/bin/env bash
created=$(tmux display-message -p '#{session_created}' 2>/dev/null) || { echo ""; exit 0; }
now=$(date +%s)
elapsed=$((now - created))
h=$((elapsed / 3600))
m=$(( (elapsed % 3600) / 60 ))
s=$((elapsed % 60))
printf "⏱ %02d:%02d:%02d" "$h" "$m" "$s"
UPTIME

  chmod +x "$bin_dir/tmux-uptime"
}

install_spotify_script() {
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/tmux-spotify" << 'SPOTIFY'
#!/usr/bin/env bash
if ! pgrep -x Spotify &>/dev/null; then
  echo ""; exit 0
fi

state=$(osascript -e 'tell application "Spotify" to player state' 2>/dev/null) || { echo ""; exit 0; }

if [[ "$state" == "playing" ]]; then
  artist=$(osascript -e 'tell application "Spotify" to artist of current track' 2>/dev/null)
  track=$(osascript -e 'tell application "Spotify" to name of current track' 2>/dev/null)
  combined="$artist – $track"
  (( ${#combined} > 45 )) && combined="${combined:0:42}…"
  echo "♫ $combined"
elif [[ "$state" == "paused" ]]; then
  echo "⏸ Paused"
else
  echo ""
fi
SPOTIFY

  chmod +x "$bin_dir/tmux-spotify"
  export PATH="$bin_dir:$PATH"
}

# ──────────────────────────────────────────────
# WORKTREE MANAGEMENT
# ──────────────────────────────────────────────
resolve_worktree() {
  local branch="$1"

  # If the requested branch IS the current branch in the main worktree,
  # just use the repo root — no separate worktree needed.
  if [[ "$branch" == "$(current_branch)" ]] && \
     git worktree list --porcelain | awk '/^worktree/{wt=$2} /^branch/{if($2=="refs/heads/'"$branch"'") print wt}' \
       | grep -q "^$REPO_ROOT$"; then
    info "Already on '$branch' in main worktree — using $REPO_ROOT"
    echo "$REPO_ROOT"
    return
  fi

  local worktree_path="$WORKTREES_DIR/$(basename "$REPO_ROOT")/$branch"

  # Already registered with git → reuse
  if git worktree list --porcelain | grep -q "^worktree $worktree_path$"; then
    info "Worktree already exists at $worktree_path — reusing."
    echo "$worktree_path"
    return
  fi

  # Stale directory (not tracked by git) → clean up
  if [[ -d "$worktree_path" ]]; then
    info "Stale directory found — removing and re-creating worktree."
    rm -rf "$worktree_path"
  fi

  mkdir -p "$(dirname "$worktree_path")"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    info "Branch '$branch' exists locally — creating worktree."
    git worktree add "$worktree_path" "$branch" >&2
  elif git ls-remote --exit-code --heads origin "$branch" &>/dev/null; then
    info "Branch '$branch' found on remote — tracking from origin/$branch."
    git worktree add --track -b "$branch" "$worktree_path" "origin/$branch" >&2
  else
    info "Branch '$branch' not found — creating new branch + worktree."
    git worktree add -b "$branch" "$worktree_path" >&2
  fi

  echo "$worktree_path"
}

# ──────────────────────────────────────────────
# TMUX SESSION
# ──────────────────────────────────────────────
launch_tmux() {
  local branch="$1"
  local worktree_path="$2"
  # Sanitise session name (tmux dislikes slashes)
  local session="${SESSION_PREFIX}_${branch//\//_}"

  if tmux has-session -t "$session" 2>/dev/null; then
    info "Session '$session' already running — attaching."
    tmux attach-session -t "$session"
    return
  fi

  info "Launching tmux session '$session' in $worktree_path"

  tmux new-session -d -s "$session" -c "$worktree_path"
  tmux send-keys -t "$session" "claude" Enter
  tmux split-window -h -t "${session}:" -c "$worktree_path" \
    "zsh -c 'echo \"\" && gd=\$(git rev-parse --git-dir 2>/dev/null); gc=\$(git rev-parse --git-common-dir 2>/dev/null); if [[ \"\$gd\" != \"\$gc\" ]]; then printf \"  \033[1;38;5;208m⚠ Worktree\033[0m  (linked to \$gc)\n\n\"; fi && printf \"  \033[1;38;5;39m┌─────────────────────────────────┐\033[0m\n\" && printf \"  \033[1;38;5;39m│\033[0m  \033[1;37mRecent commits\033[0m                 \033[1;38;5;39m│\033[0m\n\" && printf \"  \033[1;38;5;39m└─────────────────────────────────┘\033[0m\n\" && echo \"\" && git log --oneline --decorate --color=always -3 2>/dev/null | sed \"s/^/  /\" && echo \"\" && printf \"  \033[1;38;5;39m┌─────────────────────────────────┐\033[0m\n\" && printf \"  \033[1;38;5;39m│\033[0m  \033[1;37mtmux cheatsheet\033[0m                \033[1;38;5;39m│\033[0m\n\" && printf \"  \033[1;38;5;39m└─────────────────────────────────┘\033[0m\n\" && echo \"\" && printf \"  \033[38;5;245mCtrl-b d\033[0m    detach session\n\" && printf \"  \033[38;5;245mCtrl-b ←→\033[0m   switch pane\n\" && printf \"  \033[38;5;245mCtrl-b z\033[0m    zoom pane\n\" && printf \"  \033[38;5;245mCtrl-b c\033[0m    new window\n\" && printf \"  \033[38;5;245mCtrl-b n/p\033[0m  next/prev window\n\" && printf \"  \033[38;5;245mCtrl-b [\033[0m    scroll mode\n\" && printf \"  \033[38;5;245mCtrl-b x\033[0m    kill pane\n\" && echo \"\" && printf \"  \033[38;5;238m──────────────────────────────────\033[0m\n\" && echo \"\" && exec zsh'"

  # ── Status bar ──────────────────────────────
  tmux set-option -t "$session" status-interval 5

  tmux set-option -t "$session" status-left-length 40
  tmux set-option -t "$session" status-left \
    "#[fg=colour39,bold] ⎇  ${branch} #[fg=default]│ "

  tmux set-option -t "$session" status-right-length 80
  tmux set-option -t "$session" status-right \
    "#(tmux-uptime) #[fg=colour245]│ #(tmux-spotify) #[fg=colour245]│ %H:%M "

  # Enable native terminal mouse selection (bypass tmux mouse mode)
  tmux set-option -t "$session" mouse off

  # Tokyo Night-ish palette
  tmux set-option -t "$session" status-style                "bg=colour235,fg=colour252"
  tmux set-option -t "$session" status-left-style           "fg=colour39,bold"
  tmux set-option -t "$session" status-right-style          "fg=colour39"
  tmux set-option -t "$session" pane-border-style           "fg=colour238"
  tmux set-option -t "$session" pane-active-border-style    "fg=colour39"
  tmux set-option -t "$session" window-status-current-style "fg=colour39,bold"

  # Focus the Claude pane (first pane of first window)
  local first_win
  first_win=$(tmux list-windows -t "$session" -F '#{window_index}' | head -1)
  local first_pane
  first_pane=$(tmux list-panes -t "$session:$first_win" -F '#{pane_index}' | head -1)
  tmux select-pane -t "$session:$first_win.$first_pane"

  tmux attach-session -t "$session"
}

# ──────────────────────────────────────────────
# KILL / CLEANUP
# ──────────────────────────────────────────────
kill_session() {
  local branch="${1:-}"

  if [[ -z "$branch" ]]; then
    # List active dev sessions and let the user pick
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
      | grep "^${SESSION_PREFIX}_" || true)

    if [[ -z "$sessions" ]]; then
      die "No active dev sessions found."
    fi

    echo "Active dev sessions:" >&2
    echo "$sessions" | nl -ba >&2
    read -rp "Session to kill (name or number, 'all' to kill all): " choice

    if [[ "$choice" == "all" ]]; then
      echo "$sessions" | while read -r s; do
        info "Killing session '$s'"
        tmux kill-session -t "$s" 2>/dev/null || true
      done
      info "All dev sessions killed."
      return
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
      branch=$(echo "$sessions" | sed -n "${choice}p")
      [[ -z "$branch" ]] && die "Invalid selection."
      info "Killing session '$branch'"
      tmux kill-session -t "$branch" 2>/dev/null || true
      return
    else
      branch="$choice"
    fi
  fi

  # Sanitise the same way launch_tmux does
  local session
  if tmux has-session -t "$branch" 2>/dev/null; then
    session="$branch"
  else
    session="${SESSION_PREFIX}_${branch//\//_}"
  fi

  if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session"
    info "Session '$session' killed."
  else
    die "No tmux session found for '$session'."
  fi
}

# ──────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────
main() {
  # dev-kill subcommand
  if [[ "${1:-}" == "kill" ]]; then
    shift
    kill_session "$@"
    return
  fi

  require_git

  local branch="${1:-}"

  if [[ -z "$branch" ]]; then
    local cur
    cur=$(current_branch)
    read -rp "Branch name [Enter to stay on '$cur']: " branch
    # Empty input → stay on current branch, no worktree needed
    if [[ -z "$branch" ]]; then
      branch="$cur"
      info "No branch entered — staying on '$branch'."
    fi
  fi

  install_spotify_script
  install_timer_script

  local use_worktree="n"
  local cur
  cur=$(current_branch)
  if [[ "$branch" != "$cur" ]]; then
    read -rp "Use a worktree for '$branch'? [y/N]: " use_worktree
  fi

  local worktree_path
  if [[ "$use_worktree" =~ ^[Yy]$ ]]; then
    worktree_path=$(resolve_worktree "$branch")
  else
    worktree_path="$(pwd -P)"
  fi

  launch_tmux "$branch" "$worktree_path"
}

main "$@"