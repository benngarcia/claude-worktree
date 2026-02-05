# frozen_string_literal: true

require 'open3'
require 'fileutils'
require_relative 'config'

module Cwt
  class Repository
    WORKTREE_DIR = ".worktrees"
    CONFIG_DIR = ".cwt"

    attr_reader :root, :project_root, :parent_repository

    # Find repo root from any path (including from within worktrees)
    def self.discover(start_path = Dir.pwd)
      Dir.chdir(start_path) do
        stdout, status = Open3.capture2("git", "rev-parse", "--path-format=absolute", "--git-common-dir")
        return nil unless status.success?

        git_common_dir = stdout.strip
        return nil if git_common_dir.empty?

        # --git-common-dir returns /path/to/repo/.git, so strip the /.git
        new(git_common_dir.sub(%r{/\.git$}, ''))
      end
    rescue Errno::ENOENT
      nil
    end

    # Discover all repositories (parent + nested) from start path
    def self.discover_all(start_path = Dir.pwd)
      primary = discover(start_path)
      return [] unless primary

      # Find project root (topmost parent with .cwt)
      project_root = primary.find_project_root

      if project_root && project_root != primary.root
        # We're in a nested repo, return parent as primary
        parent = new(project_root)
        parent.set_project_root(project_root)
        [parent] + parent.nested_repositories
      else
        # We're in the parent repo (or standalone)
        primary.set_project_root(primary.root)
        [primary] + primary.nested_repositories
      end
    end

    def initialize(root, parent: nil)
      @root = File.expand_path(root)
      @parent_repository = parent
      @project_root = parent&.project_root || @root
      @config = nil
    end

    def set_project_root(path)
      @project_root = File.expand_path(path)
    end

    def config
      @config ||= Config.new(@root)
    end

    def name
      File.basename(@root)
    end

    def nested?
      @parent_repository != nil
    end

    def worktrees_dir
      File.join(@root, WORKTREE_DIR)
    end

    def config_dir
      File.join(@root, CONFIG_DIR)
    end

    def setup_script_path
      File.join(config_dir, "setup")
    end

    def teardown_script_path
      File.join(config_dir, "teardown")
    end

    def has_setup_script?
      File.exist?(setup_script_path) && File.executable?(setup_script_path)
    end

    def has_teardown_script?
      File.exist?(teardown_script_path) && File.executable?(teardown_script_path)
    end

    # Find the project root by walking up to find topmost .cwt directory
    def find_project_root
      current = @root
      found_root = nil

      while current != "/"
        if File.directory?(File.join(current, CONFIG_DIR))
          found_root = current
        end
        parent = File.dirname(current)
        break if parent == current
        current = parent
      end

      found_root
    end

    # Discover nested repositories within this repo
    def nested_repositories
      nested = []

      # Check configured paths first
      config.nested_repo_paths.each do |rel_path|
        path = File.join(@root, rel_path)
        if File.directory?(path) && git_repo?(path)
          repo = Repository.new(path, parent: self)
          repo.set_project_root(@project_root)
          nested << repo
        end
      end

      # Auto-discover if enabled
      if config.auto_discover_nested?
        Dir.glob(File.join(@root, "*")).each do |path|
          next unless File.directory?(path)
          next if path.start_with?(".")  # Skip hidden directories
          next if File.basename(path) == WORKTREE_DIR
          next if nested.any? { |r| r.root == File.expand_path(path) }  # Skip already found

          if git_repo?(path)
            repo = Repository.new(path, parent: self)
            repo.set_project_root(@project_root)
            nested << repo
          end
        end
      end

      nested
    end

    # Returns Array<Worktree>
    def worktrees
      require_relative 'worktree'

      stdout, status = Open3.capture2("git", "-C", @root, "worktree", "list", "--porcelain")
      return [] unless status.success?

      parse_porcelain(stdout).map do |data|
        Worktree.new(
          repository: self,
          path: data[:path],
          branch: data[:branch],
          sha: data[:sha]
        )
      end
    end

    def find_worktree(name_or_path)
      # Normalize path for comparison (handles macOS /var -> /private/var symlinks)
      normalized_path = begin
        File.realpath(name_or_path)
      rescue Errno::ENOENT
        File.expand_path(name_or_path)
      end

      worktrees.find do |wt|
        wt.name == name_or_path || wt.path == normalized_path
      end
    end

    # Create a new worktree with the given name
    # Returns { success: true, worktree: Worktree } or { success: false, error: String }
    def create_worktree(name)
      require_relative 'worktree'

      # Sanitize name
      safe_name = name.strip.gsub(/[^a-zA-Z0-9_\-]/, '_')
      path = File.join(worktrees_dir, safe_name)
      absolute_path = File.join(@root, WORKTREE_DIR, safe_name)

      # Ensure .worktrees exists
      FileUtils.mkdir_p(worktrees_dir)

      # Create worktree with new branch
      cmd = ["git", "-C", @root, "worktree", "add", "-b", safe_name, path]
      _stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        return { success: false, error: stderr }
      end

      # Create worktree object
      worktree = Worktree.new(
        repository: self,
        path: absolute_path,
        branch: safe_name,
        sha: nil # Will be populated on next list
      )

      # Mark as needing setup
      worktree.mark_needs_setup!

      { success: true, worktree: worktree }
    end

    private

    def git_repo?(path)
      git_dir = File.join(path, ".git")
      File.exist?(git_dir) # Works for both directory and file (worktree)
    end

    def parse_porcelain(output)
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
  end
end
