# frozen_string_literal: true

module Cwt
  class Model
    attr_reader :repositories, :primary_repository, :selection_index, :mode, :input_buffer, :message, :running, :fetch_generation, :filter_query
    attr_accessor :resume_to  # Worktree object or nil
    attr_accessor :show_all_repos  # Toggle between current repo and all repos
    attr_accessor :selected_repo_index  # For creating worktrees in specific repo

    def initialize(repositories)
      @repositories = Array(repositories)
      @primary_repository = @repositories.first
      @worktrees_cache = []
      @selection_index = 0
      @mode = :normal # :normal, :creating, :filtering, :selecting_repo
      @input_buffer = String.new
      @filter_query = String.new
      @message = "Welcome to CWT"
      @running = true
      @fetch_generation = 0
      @resume_to = nil
      @show_all_repos = true  # Default to showing all repos
      @selected_repo_index = 0
    end

    # Backward compatibility - return primary repository
    def repository
      @primary_repository
    end

    def worktrees
      @worktrees_cache
    end

    def refresh_worktrees!
      if @show_all_repos
        # Collect worktrees from all repositories
        @worktrees_cache = @repositories.flat_map(&:worktrees)
      else
        # Only primary repository
        @worktrees_cache = @primary_repository.worktrees
      end
      clamp_selection
      @worktrees_cache
    end

    def update_worktrees(list)
      @worktrees_cache = list
      clamp_selection
    end

    def find_worktree_by_path(path)
      # Normalize path for comparison (handles macOS /var -> /private/var symlinks)
      normalized = begin
        File.realpath(path)
      rescue Errno::ENOENT
        File.expand_path(path)
      end
      @worktrees_cache.find { |wt| wt.path == normalized }
    end

    def visible_worktrees
      list = if @filter_query.empty?
        @worktrees_cache
      else
        @worktrees_cache.select do |wt|
          wt.path.include?(@filter_query) ||
          (wt.branch && wt.branch.include?(@filter_query)) ||
          wt.repository.name.include?(@filter_query)
        end
      end

      # Sort by repository for grouped display (parent first, then nested)
      list.sort_by do |wt|
        parent_name = wt.repository.parent_repository&.name || wt.repository.name
        nested_order = wt.repository.nested? ? 1 : 0
        main_order = wt.main? ? 0 : 1  # Repository root first, then .worktrees/
        [parent_name, nested_order, wt.repository.name, main_order, wt.name]
      end
    end

    # Group worktrees by repository for display
    def worktrees_by_repository
      visible_worktrees.group_by { |wt| wt.repository }
    end

    def increment_generation
      @fetch_generation += 1
    end

    def move_selection(delta)
      list = visible_worktrees
      return if list.empty?

      new_index = @selection_index + delta
      if new_index >= 0 && new_index < list.size
        @selection_index = new_index
      end
    end

    def set_mode(mode)
      @mode = mode
      if mode == :creating
        @input_buffer = String.new
        @selected_repo_index = 0
        @message = "Enter session name (Tab to change repo): "
      elsif mode == :filtering
        @message = "Filter: "
        # We don't clear filter query here, we assume user wants to edit it
      elsif mode == :selecting_repo
        @message = "Select repository: "
      else
        @message = "Ready"
      end
    end

    def set_filter(query)
      @filter_query = query
      @selection_index = 0 # Reset selection on filter change
    end

    def input_append(char)
      if @mode == :filtering
        @filter_query << char
        @selection_index = 0
      else
        @input_buffer << char
      end
    end

    def input_backspace
      if @mode == :filtering
        @filter_query.chop!
        @selection_index = 0
      else
        @input_buffer.chop!
      end
    end

    def set_message(msg)
      @message = msg
    end

    def selected_worktree
      visible_worktrees[@selection_index]
    end

    # Get the repository to create worktree in
    def target_repository
      @repositories[@selected_repo_index] || @primary_repository
    end

    def cycle_target_repo
      @selected_repo_index = (@selected_repo_index + 1) % @repositories.size
    end

    def toggle_show_all_repos
      @show_all_repos = !@show_all_repos
      refresh_worktrees!
    end

    def quit
      @running = false
    end

    private

    def clamp_selection
      list = visible_worktrees
      if list.empty?
        @selection_index = 0
      elsif @selection_index >= list.size
        @selection_index = list.size - 1
      end
    end
  end
end
