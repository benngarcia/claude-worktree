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

    SETUP_MARKER = ".cwt_needs_setup"

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

      # Mark worktree as needing setup (will run on first resume)
      mark_needs_setup(path)

      { success: true, path: path }
    end

    def self.needs_setup?(path)
      File.exist?(File.join(path, SETUP_MARKER))
    end

    def self.mark_needs_setup(path)
      FileUtils.touch(File.join(path, SETUP_MARKER))
    end

    def self.mark_setup_complete(path)
      marker = File.join(path, SETUP_MARKER)
      File.delete(marker) if File.exist?(marker)
    end

    def self.run_setup_visible(path)
      root = Dir.pwd
      setup_script = File.join(root, ".cwt", "setup")

      if File.exist?(setup_script) && File.executable?(setup_script)
        puts "\e[1;36m=== Running .cwt/setup ===\e[0m"
        puts

        success = Dir.chdir(path) do
          system({ "CWT_ROOT" => root }, setup_script)
        end

        puts

        unless success
          puts "\e[1;33mWarning: .cwt/setup failed (exit code: #{$?.exitstatus})\e[0m"
          print "Press Enter to continue or Ctrl+C to abort..."
          begin
            STDIN.gets
          rescue Interrupt
            raise
          end
        end
      else
        # Default behavior: Symlink .env and node_modules (silent, fast)
        setup_default_symlinks(path, root)
      end
    end

    def self.run_teardown(path)
      root = Dir.pwd
      teardown_script = File.join(root, ".cwt", "teardown")

      return { ran: false } unless File.exist?(teardown_script) && File.executable?(teardown_script)

      puts "\e[1;36m=== Running .cwt/teardown ===\e[0m"
      puts

      success = Dir.chdir(path) do
        system({ "CWT_ROOT" => root }, teardown_script)
      end

      puts

      { ran: true, success: success }
    end

    def self.remove_worktree(path, force: false)
      # Step 0: Run teardown script if directory exists
      if Dir.exist?(path)
        result = run_teardown(path)
        if result[:ran] && !result[:success] && !force
          return { success: false, error: "Teardown script failed. Use 'D' to force delete." }
        end
      end

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

    def self.setup_default_symlinks(target_path, root)
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