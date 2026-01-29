module Cwt
  class Model
    attr_reader :worktrees, :selection_index, :mode, :input_buffer, :message, :running, :fetch_generation, :filter_query

    def initialize
      @worktrees = []
      @selection_index = 0
      @mode = :normal # :normal, :creating, :filtering
      @input_buffer = String.new
      @filter_query = String.new
      @message = "Welcome to CWT"
      @running = true
      @fetch_generation = 0
    end

    def update_worktrees(list)
      @worktrees = list
      clamp_selection
    end

    def visible_worktrees
      if @filter_query.empty?
        @worktrees
      else
        @worktrees.select { |wt| wt[:path].include?(@filter_query) || (wt[:branch] && wt[:branch].include?(@filter_query)) }
      end
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
        @message = "Enter session name: "
      elsif mode == :filtering
        @message = "Filter: "
        # We don't clear filter query here, we assume user wants to edit it
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
