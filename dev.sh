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

set -euo pipefail

# ──────────────────────────────────────────────
# CONFIG — override via env vars in your shell profile
# ──────────────────────────────────────────────
WORKTREES_DIR="${WORKTREES_DIR:-$HOME/worktrees}"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --toplevel 2>/dev/null || echo "$PWD")}"
SESSION_PREFIX="dev"

# ──────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────
die()  { echo "❌  $*" >&2; exit 1; }
info() { echo "→  $*"; }

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
    git worktree add "$worktree_path" "$branch"
  elif git ls-remote --exit-code --heads origin "$branch" &>/dev/null; then
    info "Branch '$branch' found on remote — tracking from origin/$branch."
    git worktree add --track -b "$branch" "$worktree_path" "origin/$branch"
  else
    info "Branch '$branch' not found — creating new branch + worktree."
    git worktree add -b "$branch" "$worktree_path"
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
  local session="${SESSION_PREFIX}:${branch//\//-}"

  if tmux has-session -t "$session" 2>/dev/null; then
    info "Session '$session' already running — attaching."
    tmux attach-session -t "$session"
    return
  fi

  info "Launching tmux session '$session' in $worktree_path"

  tmux new-session -d -s "$session" -c "$worktree_path"
  tmux split-window -h -t "$session" -c "$worktree_path"
  tmux select-pane -t "$session:0.0"

  # ── Status bar ──────────────────────────────
  tmux set-option -t "$session" status-interval 5

  tmux set-option -t "$session" status-left-length 40
  tmux set-option -t "$session" status-left \
    "#[fg=colour39,bold] ⎇  ${branch} #[fg=default]│ "

  tmux set-option -t "$session" status-right-length 80
  tmux set-option -t "$session" status-right \
    "#(tmux-spotify) #[fg=colour245]│ %H:%M "

  # Tokyo Night-ish palette
  tmux set-option -t "$session" status-style                "bg=colour235,fg=colour252"
  tmux set-option -t "$session" status-left-style           "fg=colour39,bold"
  tmux set-option -t "$session" status-right-style          "fg=colour39"
  tmux set-option -t "$session" pane-border-style           "fg=colour238"
  tmux set-option -t "$session" pane-active-border-style    "fg=colour39"
  tmux set-option -t "$session" window-status-current-style "fg=colour39,bold"

  tmux attach-session -t "$session"
}

# ──────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────
main() {
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

  local worktree_path
  worktree_path=$(resolve_worktree "$branch")

  launch_tmux "$branch" "$worktree_path"
}

main "$@"