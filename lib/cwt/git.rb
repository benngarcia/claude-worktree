# frozen_string_literal: true

require 'open3'
require 'fileutils'

module Cwt
  class Git
    WORKTREE_DIR = ".worktrees"

    def self.list_worktrees
      # -C . ensures we run from current dir, though we are usually there.
      stdout, status = Open3.capture2("git", "worktree", "list", "--porcelain")
      return [] unless status.success?

      parse_porcelain(stdout)
    end

    def self.get_commit_ages(shas)
      return {} if shas.empty?
      
      # Batch fetch commit times
      # %H: full hash, %cr: relative date
      cmd = ["git", "--no-optional-locks", "show", "-s", "--format=%H|%cr"] + shas
      stdout, status = Open3.capture2(*cmd)
      return {} unless status.success?

      ages = {}
      stdout.each_line do |line|
        parts = line.strip.split('|')
        if parts.size == 2
          ages[parts[0]] = parts[1]
        end
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
    rescue => e
      { dirty: false }
    end

    def self.add_worktree(name)
      # Sanitize name
      safe_name = name.strip.gsub(/[^a-zA-Z0-9_\-]/, '_')
      path = File.join(WORKTREE_DIR, safe_name)

      # Ensure .worktrees exists
      FileUtils.mkdir_p(WORKTREE_DIR)

      # Create worktree
      # We create a new branch with the same name as the worktree
      cmd = ["git", "worktree", "add", "-b", safe_name, path]
      _stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        return { success: false, error: stderr }
      end

      # Post-creation setup: Copy .env if it exists
      setup_environment(path)

      { success: true, path: path }
    end

    def self.remove_worktree(path, force: false)
      # Step 1: Cleanup symlinks/copies (Best effort)
      # This helps 'safe delete' succeed if only untracked files are present.
      [".env", "node_modules"].each do |file|
        target_path = File.join(path, file)
        if File.exist?(target_path)
          File.delete(target_path) rescue nil
        end
      end

      # Step 2: Remove Worktree
      # Only attempt if the directory actually exists.
      # This handles the "Phantom Branch" case (worktree gone, branch remains).
      if Dir.exist?(path)
        wt_cmd = ["git", "--no-optional-locks", "worktree", "remove", path]
        wt_cmd << "--force" if force
        
        stdout, stderr, status = Open3.capture3(*wt_cmd)
        
        unless status.success?
          # If we failed to remove the worktree, we must stop unless it's a "not found" error.
          # But "not found" should be covered by Dir.exist? check mostly.
          # If git complains about dirty files, we stop here (unless force was used, which is handled by --force).
          return { success: false, error: stderr.strip }
        end
      end

      # Step 3: Delete Branch
      # The branch name is usually the basename of the path.
      branch_name = File.basename(path)
      
      branch_flag = force ? "-D" : "-d"
      stdout_b, stderr_b, status_b = Open3.capture3("git", "branch", branch_flag, branch_name)

      if status_b.success?
        { success: true }
      else
        # Branch deletion failed.
        if force
           # Force delete failed. This is weird (maybe branch doesn't exist?).
           # If branch doesn't exist, we can consider it success?
           if stderr_b.include?("not found")
             { success: true }
           else
             { success: false, error: "Worktree removed, but branch delete failed: #{stderr_b.strip}" }
           end
        else
           # Safe delete failed (unmerged commits).
           # This is a valid state: Worktree is gone, but branch remains to save data.
           { success: true, warning: "Worktree removed, but branch kept (unmerged). Use 'D' to force." }
        end
      end
    end

    def self.prune_worktrees
      Open3.capture2("git", "worktree", "prune")
    end

    private

    def self.parse_porcelain(output)
      worktrees = []
      current = {}

      output.each_line do |line|
        if line.start_with?("worktree ")
          if current.any?
            worktrees << current
            current = {}
          end
          current[:path] = line.sub("worktree ", "").strip
        elsif line.start_with?("HEAD ")
          current[:sha] = line.sub("HEAD ", "").strip
        elsif line.start_with?("branch ")
          current[:branch] = line.sub("branch ", "").strip.sub("refs/heads/", "")
        end
      end
      worktrees << current if current.any?
      worktrees
    end

    def self.setup_environment(target_path)
      root = Dir.pwd
      setup_script = File.join(root, ".cwt", "setup")

      # 1. Custom Setup Script
      if File.exist?(setup_script) && File.executable?(setup_script)
        # Execute the script inside the new worktree
        # passing the root path as an argument might be helpful, but relying on relative paths is standard.
        Open3.capture2(setup_script, chdir: target_path)
        return
      end

      # 2. Default Behavior: Symlink .env and node_modules
      files_to_link = [".env", "node_modules"]

      files_to_link.each do |file|
        source = File.join(root, file)
        target = File.join(target_path, file)

        if File.exist?(source) && !File.exist?(target)
          FileUtils.ln_s(source, target)
        end
      end
    end
  end
end