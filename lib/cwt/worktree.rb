# frozen_string_literal: true

require 'open3'
require 'fileutils'

module Cwt
  class Worktree
    SETUP_MARKER = ".cwt_needs_setup"
    DEFAULT_SYMLINKS = [".env", "node_modules"].freeze

    attr_reader :repository, :path, :branch, :sha
    attr_accessor :dirty, :last_commit

    def initialize(repository:, path:, branch:, sha:)
      @repository = repository
      @path = File.expand_path(path)
      @branch = branch
      @sha = sha
      @dirty = nil
      @last_commit = nil
    end

    def name
      File.basename(@path)
    end

    def exists?
      Dir.exist?(@path)
    end

    def main?
      @path == @repository.root
    end

    def needs_setup?
      File.exist?(setup_marker_path)
    end

    def mark_needs_setup!
      FileUtils.touch(setup_marker_path)
    end

    def mark_setup_complete!
      File.delete(setup_marker_path) if File.exist?(setup_marker_path)
    end

    # Run setup script or default symlinks
    # visible: true shows output to user, false runs silently
    def run_setup!(visible: true)
      if @repository.has_setup_script?
        run_custom_setup(visible: visible)
      else
        setup_default_symlinks
      end
    end

    # Run teardown script if it exists
    # Returns { ran: Boolean, success: Boolean }
    def run_teardown!
      return { ran: false } unless @repository.has_teardown_script?

      puts "\e[1;36m=== Running .cwt/teardown ===\e[0m"
      puts

      # Build enhanced environment variables for nested repo support
      env = build_setup_env

      success = Dir.chdir(@path) do
        system(env, @repository.teardown_script_path)
      end

      puts

      { ran: true, success: success }
    end

    # Delete this worktree and its branch
    # force: true to force delete even with uncommitted changes
    # Returns { success: Boolean, error: String?, warning: String? }
    def delete!(force: false)
      # Step 0: Run teardown script if directory exists
      if exists?
        result = run_teardown!
        if result[:ran] && !result[:success] && !force
          return { success: false, error: "Teardown script failed. Use 'D' to force delete." }
        end
      end

      # Step 1: Cleanup symlinks/copies (Best effort)
      cleanup_symlinks

      # Step 2: Remove Worktree
      if exists?
        wt_cmd = ["git", "-C", @repository.root, "worktree", "remove", @path]
        wt_cmd << "--force" if force

        _stdout, stderr, status = Open3.capture3(*wt_cmd)

        unless status.success?
          return { success: false, error: stderr.strip }
        end
      end

      # Step 3: Delete Branch
      delete_branch(force: force)
    end

    # Fetch status (dirty flag) from git
    def fetch_status!
      stdout, status = Open3.capture2(
        "git", "--no-optional-locks", "-C", @path, "status", "--porcelain"
      )
      @dirty = status.success? && !stdout.strip.empty?
      @dirty
    rescue StandardError
      @dirty = false
    end

    # Hash representation for compatibility
    def to_h
      {
        path: @path,
        branch: @branch,
        sha: @sha,
        dirty: @dirty,
        last_commit: @last_commit
      }
    end

    private

    def setup_marker_path
      File.join(@path, SETUP_MARKER)
    end

    # Build environment variables for setup/teardown scripts
    # Supports nested repository resolution
    def build_setup_env
      repo_root = File.realpath(@repository.root)
      project_root = @repository.project_root ? File.realpath(@repository.project_root) : repo_root

      # Calculate nesting depth
      nested_depth = 0
      if project_root != repo_root
        # Count directory levels between project_root and repo_root
        rel_path = repo_root.sub("#{project_root}/", "")
        nested_depth = rel_path.count("/") + 1
      end

      {
        "CWT_ROOT" => repo_root,
        "CWT_PROJECT_ROOT" => project_root,
        "CWT_WORKTREE" => @path,
        "CWT_NESTED_DEPTH" => nested_depth.to_s,
        "CWT_REPO_NAME" => @repository.name
      }
    end

    def run_custom_setup(visible: true)
      if visible
        puts "\e[1;36m=== Running .cwt/setup ===\e[0m"
        puts
      end

      # Build enhanced environment variables for nested repo support
      env = build_setup_env

      success = Dir.chdir(@path) do
        system(env, @repository.setup_script_path)
      end

      puts if visible

      unless success
        if visible
          puts "\e[1;33mWarning: .cwt/setup failed (exit code: #{$?.exitstatus})\e[0m"
          print "Press Enter to continue or Ctrl+C to abort..."
          begin
            STDIN.gets
          rescue Interrupt
            raise
          end
        end
      end

      success
    end

    def setup_default_symlinks
      DEFAULT_SYMLINKS.each do |file|
        source = File.join(@repository.root, file)
        target = File.join(@path, file)

        if File.exist?(source) && !File.exist?(target)
          FileUtils.ln_s(source, target)
        end
      end
    end

    def cleanup_symlinks
      DEFAULT_SYMLINKS.each do |file|
        target_path = File.join(@path, file)
        File.delete(target_path) if File.exist?(target_path)
      rescue StandardError
        nil
      end
    end

    def delete_branch(force: false)
      branch_flag = force ? "-D" : "-d"
      _stdout, stderr, status = Open3.capture3(
        "git", "-C", @repository.root, "branch", branch_flag, name
      )

      if status.success?
        { success: true }
      elsif force
        # Force delete failed - maybe branch doesn't exist
        if stderr.include?("not found")
          { success: true }
        else
          { success: false, error: "Worktree removed, but branch delete failed: #{stderr.strip}" }
        end
      else
        # Safe delete failed (unmerged commits) - worktree gone but branch kept
        { success: true, warning: "Worktree removed, but branch kept (unmerged). Use 'D' to force." }
      end
    end
  end
end
