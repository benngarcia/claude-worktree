# Claude Worktree (cwt)

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

**Example `.cwt/setup`:**

```bash
#!/bin/bash
# Copy .env so we can modify it safely in this session
cp ../.env .

# Install dependencies freshly (cleaner than symlinking)
npm ci

# Print a welcome message
echo "Ready to rock!"
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
| **`q`** | **Quit** |

## 🏗️ Under the Hood

*   Built in Ruby using `ratatui-ruby` for the UI.
*   Uses a simple thread pool for git operations so the UI doesn't freeze.
*   Uses `Bundler.with_unbundled_env` to ensure your session runs in a clean environment, not one polluted by this tool's dependencies.

## 🤝 Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bengarcia/claude-worktree.

## License

MIT
