# Claude Worktree (cwt)

> **Note:** This is a fork of [bucket-robotics/claude-worktree](https://github.com/bucket-robotics/claude-worktree) with extended features for nested repository support.

There are a million tools for AI coding right now. Some wrap agents in Docker containers, others proxy every shell command you type, and some try to reinvent your entire IDE.

`cwt` is a simple tool built on a simple premise: **Git worktrees are the best way to isolate AI coding sessions, but they are annoying to manage manually.**

The goal of this tool is to be as unimposing as possible. We don't want to change how you work, we just want to make the "setup" part faster.

## How it works

When you use `cwt`, you are just running a TUI (Terminal User Interface) to manage folders.

1.  **It's just Git:** Under the hood, we are just creating standard Git worktrees.
2.  **Native Environment:** When you enter a session, `cwt` suspends itself and launches a native instance of `claude` (or your preferred shell) directly in that directory.
3.  **Zero Overhead:** We don't wrap the process. We don't intercept your commands. We don't run a background daemon. Your scripts, your aliases, and your workflow remain exactly the same.

## ⚡ Features

*   **Fast Management:** Create, switch, and delete worktrees instantly.
*   **Safety Net:** cwt checks for unmerged changes before you delete a session, so you don't accidentally lose work.
*   **Auto-Setup:** Symlinks your .env and node_modules out of the box. If you need a more advanced setup, use `.cwt/setup`
*   **Nested Repository Support:** Auto-discovers nested git repos within a parent project and manages worktrees across all of them.

## 📸 Demo

![Demo](assets/demo.gif)

## 📦 Installation

```bash
gem install claude-worktree
```

Or via Homebrew Tap:
```bash
brew tap benngarcia/tap
brew install cwt
```

## 🎮 Usage

Run `cwt` in the root of any Git repository.

| Key | Action |
| :--- | :--- |
| **`n`** | **New Session** (Creates worktree & launches `claude`) |
| **`Enter`** | **Resume** (Suspends TUI, enters worktree) |
| **`/`** | **Filter** (Search by branch or folder name) |
| **`d`** | **Safe Delete** (Checks for unmerged changes first) |
| **`D`** | **Force Delete** (Shift+d - The "I know what I'm doing" option) |
| **`t`** | **Toggle View** (Switch between "all repos" and "current repo only") |
| **`Tab`** | **Cycle Repository** (When creating, select target repository) |
| **`q`** | **Quit** |

## 🪆 Nested Repository Support

When working with monorepos or projects that contain nested git repositories, `cwt` automatically discovers all nested repos and lets you manage worktrees across all of them from a single TUI.

### How it works

1. **Auto-Discovery:** When you run `cwt` from a parent repository, it scans for nested `.git` directories and includes them in the view.
2. **Grouped Display:** Worktrees are grouped by repository with visual headers. Nested repos are indented to show hierarchy.
3. **Unified Management:** Create, resume, and delete worktrees in any repository without leaving the TUI.

### Multi-Repo Workflow

```
my-project/                    # Parent repo
├── .cwt/
│   └── config.json           # Optional: configure nested repo behavior
├── backend/                   # Nested repo
│   └── .worktrees/
│       └── feat-api/
└── frontend/                  # Nested repo
    └── .worktrees/
        └── feat-ui/
```

When you run `cwt` from `my-project/`, you'll see worktrees from all three repositories in the TUI. Press `t` to toggle between viewing all repos or just the current one.

## ⚙️ Configuration

### The Setup Hook

By default, `cwt` will:

1.  Symlink `.env` from your root to the worktree.
2.  Symlink `node_modules` from your root to the worktree.

If you want to change this behavior (e.g., to run `npm ci` instead of symlinking, or to copy a different config file), simply create an executable script at `.cwt/setup`.

```bash
mkdir .cwt
touch .cwt/setup
chmod +x .cwt/setup
```

If this file exists, `cwt` will **skip the default symlinks** and execute your script inside the new worktree instead.

### Environment Variables

Setup and teardown scripts receive these environment variables:

| Variable | Description |
| :--- | :--- |
| `CWT_ROOT` | Repository root where worktree is being created |
| `CWT_PROJECT_ROOT` | Top-level parent repository (for nested repos) |
| `CWT_WORKTREE` | Path to the worktree being created |
| `CWT_NESTED_DEPTH` | Nesting level (0 = parent, 1+ = nested) |
| `CWT_REPO_NAME` | Name of the repository |

**Example `.cwt/setup`:**

```bash
#!/bin/bash

# For nested repos, symlink from project root
if [ "$CWT_NESTED_DEPTH" -gt 0 ]; then
    ln -sf "$CWT_PROJECT_ROOT/.env" .
else
    ln -sf "$CWT_ROOT/.env" .
fi

# Install dependencies freshly
npm ci

echo "Ready to rock in $CWT_REPO_NAME!"
```

### Configuration File

For advanced setups, create `.cwt/config.json` in your repository:

```json
{
  "version": 1,
  "symlinks": {
    "items": [
      { "name": ".claude", "strategy": "nearest" },
      { "name": ".mcp.json", "strategy": "nearest" },
      { "name": "CLAUDE.md", "strategy": "nearest" },
      { "name": "node_modules", "strategy": "local" },
      { "name": ".env", "strategy": "local" }
    ]
  },
  "nested_repos": {
    "auto_discover": true,
    "paths": ["backend", "frontend"]
  }
}
```

### Symlink Strategies

| Strategy | Behavior |
| :--- | :--- |
| `nearest` | Walk up directory tree to find first occurrence (default) |
| `local` | Only look in worktree's own repository |
| `parent` | Always use top-level parent repository |
| `none` | Skip symlink creation for this item |

## 🏗️ Under the Hood

*   Built in Ruby using `ratatui-ruby` for the UI.
*   Uses a simple thread pool for git operations so the UI doesn't freeze.
*   Uses `Bundler.with_unbundled_env` to ensure your session runs in a clean environment, not one polluted by this tool's dependencies.

## 🤝 Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/theluiscarbonell/claude-worktree.

## License

MIT
