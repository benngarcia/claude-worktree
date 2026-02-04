# frozen_string_literal: true

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
        # Use target repository for creation (supports multi-repo)
        target_repo = message[:repository] || model.target_repository
        result = target_repo.create_worktree(message[:name])
        if result[:success]
          model.set_message("Created worktree: #{message[:name]} in #{target_repo.name}")
          refresh_list(model)
          model.set_mode(:normal)
          model.set_filter(String.new) # Clear filter
          # Auto-enter the new session
          { type: :resume_worktree, worktree: result[:worktree] }
        else
          model.set_message("Error: #{result[:error]}")
          nil
        end
      when :delete_worktree
        worktree = message[:worktree]
        force = message[:force] || false

        result = worktree.delete!(force: force)

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
        { type: :suspend_and_resume, worktree: message[:worktree] }
      when :update_status
        return nil if message[:generation] != model.fetch_generation

        target = model.find_worktree_by_path(message[:path])
        target.dirty = message[:status][:dirty] if target
        nil
      when :update_commit_age
        return nil if message[:generation] != model.fetch_generation

        target = model.find_worktree_by_path(message[:path])
        target.last_commit = message[:age] if target
        nil
      end
    end

    def self.handle_key(model, event)
      if model.mode == :creating
        if event.enter?
          return { type: :create_worktree, name: model.input_buffer, repository: model.target_repository }
        elsif event.esc?
          model.set_mode(:normal)
        elsif event.tab?
          # Cycle through repositories
          model.cycle_target_repo
          model.set_message("Target: #{model.target_repository.name}")
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
            model.set_filter(String.new) # Clear filter
            model.set_mode(:normal) # Exit filter mode on selection
            return { type: :resume_worktree, worktree: wt }
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
          return { type: :delete_worktree, worktree: wt, force: false } if wt
        elsif event.D? # Shift+d
          wt = model.selected_worktree
          return { type: :delete_worktree, worktree: wt, force: true } if wt
        elsif event.enter?
          wt = model.selected_worktree
          if wt
            model.set_filter(String.new) # Clear filter on resume
            return { type: :resume_worktree, worktree: wt }
          end
        elsif event.r?
          return { type: :refresh_list }
        elsif event.t?
          # Toggle show all repos
          model.toggle_show_all_repos
          mode_str = model.show_all_repos ? "all repos" : "current repo only"
          model.set_message("Showing #{mode_str}")
          return :start_background_fetch
        end
      end
      nil
    end

    def self.refresh_list(model)
      model.refresh_worktrees!
    end
  end
end
