# dev.sh

A tmux workspace bootstrapper that creates per-branch development sessions with git worktree support, a Spotify status widget, and a session timer.

## Prerequisites

- **tmux** — `brew install tmux`
- **git** — any recent version
- **macOS** (optional) — the Spotify widget uses AppleScript, so it only works on macOS

## Installation

```bash
# Clone the repo
git clone <repo-url>
cd tmux

# Make the script executable
chmod +x dev.sh

# Symlink it to /usr/local/bin
sudo ln -sf "$(pwd)/dev.sh" /usr/local/bin/dev
```

## Usage

Run `dev` from inside any git repository.

```bash
# Interactive — prompts for a branch name (Enter to stay on current branch)
dev

# Jump straight to a branch
dev feature/my-branch

# Kill a session (interactive picker)
dev kill

# Kill the session for a specific branch
dev kill feature/foo

# Kill all dev sessions
dev kill all
```

## What it does

1. **Prompts for a branch** (or accepts one as an argument)
2. **Optionally creates a git worktree** so you can work on multiple branches without stashing
3. **Launches a tmux session** with:
   - Left pane: `claude` (Claude Code CLI)
   - Right pane: a shell with recent commits and a tmux cheatsheet
4. **Configures the status bar** with:
   - Current branch name
   - Session uptime timer
   - Now-playing Spotify track (macOS only)
   - Clock

## Configuration

Override these via environment variables (e.g. in your `.zshrc`):

| Variable | Default | Description |
|---|---|---|
| `WORKTREES_DIR` | `~/worktrees` | Where git worktrees are created |
| `REPO_ROOT` | Auto-detected via `git rev-parse` | Root of the current git repo |

## Uninstall

```bash
rm /usr/local/bin/dev
rm ~/.local/bin/tmux-spotify
rm ~/.local/bin/tmux-uptime
```
