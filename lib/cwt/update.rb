# frozen_string_literal: true

require_relative "git"

module Cwt
  class Update
    def self.handle(model, message)
      case message[:type]
      when :tick
        nil
      when :quit
        model.quit
      when :key_press
        handle_key(model, message[:key])
      when :refresh_list
        refresh_list(model)
        :start_background_fetch
      when :create_worktree
        result = Git.add_worktree(message[:name])
        if result[:success]
          model.set_message("Created worktree: #{message[:name]}")
          refresh_list(model)
          model.set_mode(:normal)
          model.set_filter(String.new) # Clear filter
          # Auto-enter the new session
          # We return the resume command directly. 
          # The App will execute resume, which involves suspend->run->restore->refresh->fetch
          { type: :resume_worktree, path: result[:path] }
        else
          model.set_message("Error: #{result[:error]}")
          nil
        end
      when :delete_worktree
        path = message[:path]
        force = message[:force] || false
        
        result = Git.remove_worktree(path, force: force)
        
        if result[:success]
          if result[:warning]
            model.set_message("Warning: #{result[:warning]}. Use 'D' to force delete.")
          else
            model.set_message("Deleted worktree")
          end
          refresh_list(model)
          :start_background_fetch
        else
          model.set_message("Error deleting: #{result[:error]}. Use 'D' to force delete.")
          nil
        end
      when :resume_worktree
        { type: :suspend_and_resume, path: message[:path] }
      when :update_status
        return nil if message[:generation] != model.fetch_generation
        
        target = model.worktrees.find { |wt| wt[:path] == message[:path] }
        if target
          target[:dirty] = message[:status][:dirty]
        end
        nil
      when :update_commit_age
        return nil if message[:generation] != model.fetch_generation

        target = model.worktrees.find { |wt| wt[:path] == message[:path] }
        if target
          target[:last_commit] = message[:age]
        end
        nil
      end
    end

    def self.handle_key(model, event)
      if model.mode == :creating
        if event.enter?
          return { type: :create_worktree, name: model.input_buffer }
        elsif event.esc?
          model.set_mode(:normal)
        elsif event.backspace?
          model.input_backspace
        elsif event.to_s.length == 1
          model.input_append(event.to_s)
        end
      elsif model.mode == :filtering
        if event.enter?
          # Select current item and resume
          wt = model.selected_worktree
          if wt
            path = wt[:path]
            model.set_filter(String.new) # Clear filter
            model.set_mode(:normal) # Exit filter mode on selection
            return { type: :resume_worktree, path: path } 
          else
            model.set_mode(:normal)
          end
        elsif event.esc?
          model.set_filter(String.new) # Clear filter
          model.set_mode(:normal)
        elsif event.backspace?
          model.input_backspace
        elsif event.down? || event.ctrl_n?
          model.move_selection(1)
        elsif event.up? || event.ctrl_p?
          model.move_selection(-1)
        elsif event.to_s.length == 1
          model.input_append(event.to_s)
        end
      else
        # Normal Mode
        if event.q? || event.ctrl_c?
          return { type: :quit }
        elsif event.j? || event.down?
          model.move_selection(1)
        elsif event.k? || event.up?
          model.move_selection(-1)
        elsif event.n?
          model.set_mode(:creating)
        elsif event.slash? # / key
          model.set_mode(:filtering)
        elsif event.d?
          wt = model.selected_worktree
          return { type: :delete_worktree, path: wt[:path], force: false } if wt
        elsif event.D? # Shift+d
          wt = model.selected_worktree
          return { type: :delete_worktree, path: wt[:path], force: true } if wt
        elsif event.enter?
          wt = model.selected_worktree
          if wt
            path = wt[:path]
            model.set_filter(String.new) # Clear filter on resume
            return { type: :resume_worktree, path: path }
          end
        elsif event.r?
          return { type: :refresh_list }
        end
      end
      nil
    end

    def self.refresh_list(model)
      list = Git.list_worktrees
      model.update_worktrees(list)
    end
  end
end
