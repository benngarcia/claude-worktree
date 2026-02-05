# frozen_string_literal: true

require 'open3'

module Cwt
  # Thin wrapper around git commands.
  # Business logic lives in Repository and Worktree classes.
  class Git
    def self.get_commit_ages(shas, repo_root: nil)
      return {} if shas.empty?

      # Batch fetch commit times
      # %H: full hash, %cr: relative date
      cmd = ["git"]
      cmd += ["-C", repo_root] if repo_root
      cmd += ["--no-optional-locks", "show", "-s", "--format=%H|%cr"] + shas

      stdout, _stderr, status = Open3.capture3(*cmd)
      return {} unless status.success?

      ages = {}
      stdout.each_line do |line|
        parts = line.strip.split('|')
        ages[parts[0]] = parts[1] if parts.size == 2
      end
      ages
    end

    def self.get_status(path)
      # Check for uncommitted changes
      # --no-optional-locks: Prevent git from writing to the index (lock contention)
      # -C path: Run git in that directory
      # --porcelain: stable output
      dirty_cmd = ["git", "--no-optional-locks", "-C", path, "status", "--porcelain"]
      stdout_dirty, status_dirty = Open3.capture2(*dirty_cmd)
      is_dirty = status_dirty.success? && !stdout_dirty.strip.empty?

      { dirty: is_dirty }
    rescue StandardError
      { dirty: false }
    end

    def self.prune_worktrees(repo_root: nil)
      cmd = ["git"]
      cmd += ["-C", repo_root] if repo_root
      cmd << "worktree" << "prune"
      Open3.capture2(*cmd)
    end
  end
end
