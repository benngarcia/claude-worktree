## [Unreleased]

## [0.3.0] - 2026-02-03

### Added
- **Nested Repository Support**: Auto-discovers nested git repos within parent project
- **Multi-Repo TUI**: View and manage worktrees across all repositories with grouped display
- **Configuration File**: Optional `.cwt/config.json` for symlink strategies and nested repo settings
- **New Environment Variables**: `CWT_PROJECT_ROOT`, `CWT_NESTED_DEPTH`, `CWT_WORKTREE`, `CWT_REPO_NAME`
- **Toggle View**: Press `t` to switch between all repos and current repo only
- **Repo Selection**: Press `Tab` when creating to cycle target repository

### Changed
- `Repository.discover_all` now returns parent + all nested repositories
- Setup scripts receive enhanced environment for nested repo awareness
- TUI groups worktrees by repository with visual headers

## [0.1.4] - 2026-01-30

### Added
- **Permanent CD on exit**: After quitting cwt, your shell stays in the last resumed worktree directory
- **Visible setup output**: `.cwt/setup` script now runs with visible output on first resume (not during worktree creation)
- **Teardown support**: Optional `.cwt/teardown` script runs before worktree deletion
- **CWT_ROOT environment variable**: Setup and teardown scripts receive `$CWT_ROOT` pointing to the repo root
- Integration tests for setup/teardown functionality
- Homebrew update instructions in deploy script

### Changed
- Setup now runs on first resume instead of during worktree creation
- Setup only runs once per worktree (tracked via `.cwt_needs_setup` marker)

## [0.1.0] - 2026-01-29

- Initial release
