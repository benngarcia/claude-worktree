# frozen_string_literal: true

require "ratatui_ruby"
require "thread"
require_relative "model"
require_relative "view"
require_relative "update"
require_relative "git"

module Cwt
  class App
    POOL_SIZE = 4

    def self.run
      model = Model.new
      
      # Initialize Thread Pool
      @worker_queue = Queue.new
      @workers = POOL_SIZE.times.map do
        Thread.new do
          while task = @worker_queue.pop
            # Process task
            begin
              case task[:type]
              when :fetch_status
                status = Git.get_status(task[:path])
                task[:result_queue] << { 
                  type: :update_status, 
                  path: task[:path], 
                  status: status, 
                  generation: task[:generation] 
                }
              end
            rescue => e
              # Ignore worker errors
            end
          end
        end
      end

      # Initial Load
      Update.refresh_list(model)
      
      # Main Event Queue
      main_queue = Queue.new
      start_background_fetch(model, main_queue)

      RatatuiRuby.run do |tui|
        while model.running
          tui.draw do |frame|
            View.draw(model, tui, frame)
          end

          event = tui.poll_event(timeout: 0.1)

          # Process TUI Event
          cmd = nil
          if event.key?
            cmd = Update.handle(model, { type: :key_press, key: event })
          elsif event.resize?
            # Layout auto-handles
          elsif event.none?
            cmd = Update.handle(model, { type: :tick })
          end

          handle_command(cmd, model, tui, main_queue) if cmd

          # Process Background Queue
          while !main_queue.empty?
            msg = main_queue.pop(true) rescue nil
            if msg
              Update.handle(model, msg)
            end
          end
        end
      end

      # After TUI exits, cd into last worktree if one was resumed
      if model.exit_directory && Dir.exist?(model.exit_directory)
        Dir.chdir(model.exit_directory)
        exec ENV.fetch('SHELL', '/bin/zsh')
      end
    end

    def self.handle_command(cmd, model, tui, main_queue)
      return unless cmd

      if cmd == :start_background_fetch
        start_background_fetch(model, main_queue)
        return
      end

      # Cmd is a hash
      case cmd[:type]
      when :quit
        model.quit
      when :delete_worktree
        # Suspend TUI for visible teardown output
        RatatuiRuby.restore_terminal
        puts "\e[H\e[2J" # Clear screen
        result = Update.handle(model, cmd)
        RatatuiRuby.init_terminal
        handle_command(result, model, tui, main_queue)
      when :create_worktree, :refresh_list
        result = Update.handle(model, cmd)
        handle_command(result, model, tui, main_queue)
      when :resume_worktree, :suspend_and_resume
        suspend_tui_and_run(cmd[:path], model, tui)
        Update.refresh_list(model)
        start_background_fetch(model, main_queue)
      end
    end

    def self.start_background_fetch(model, main_queue)
      # Increment generation to invalidate old results
      model.increment_generation
      current_gen = model.fetch_generation

      worktrees = model.worktrees
      
      # Batch fetch commit ages (Fast enough to do on main thread or one-off thread? 
      # Git.get_commit_ages is fast. Let's do it in a one-off thread to not block UI)
      Thread.new do
        shas = worktrees.map { |wt| wt[:sha] }.compact
        ages = Git.get_commit_ages(shas)
        
        worktrees.each do |wt|
          if age = ages[wt[:sha]]
            main_queue << { 
              type: :update_commit_age, 
              path: wt[:path], 
              age: age, 
              generation: current_gen 
            }
          end
        end
      end

      # Queue Status Checks (Worker Pool)
      worktrees.each do |wt|
        @worker_queue << { 
          type: :fetch_status, 
          path: wt[:path], 
          result_queue: main_queue, 
          generation: current_gen 
        }
      end
    end

    def self.suspend_tui_and_run(path, model, tui)
      RatatuiRuby.restore_terminal

      puts "\e[H\e[2J" # Clear screen

      # Run setup if this is a new worktree
      if Git.needs_setup?(path)
        begin
          Git.run_setup_visible(path)
          Git.mark_setup_complete(path)
        rescue Interrupt
          puts "\nSetup aborted."
          RatatuiRuby.init_terminal
          return
        end
      end

      puts "Launching claude in #{path}..."
      begin
        Dir.chdir(path) do
          if defined?(Bundler)
            Bundler.with_unbundled_env { system("claude") }
          else
            system("claude")
          end
        end
        # Track last resumed path for exit
        model.exit_directory = path
      rescue => e
        puts "Error: #{e.message}"
        print "Press any key to return..."
        STDIN.getc
      ensure
        RatatuiRuby.init_terminal
      end
    end
  end
end