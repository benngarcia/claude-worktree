# frozen_string_literal: true

require "ratatui_ruby"
require "thread"
require_relative "repository"
require_relative "worktree"
require_relative "model"
require_relative "view"
require_relative "update"
require_relative "git"

module Cwt
  class App
    POOL_SIZE = 4

    def self.run
      # Discover all repositories (parent + nested) from current directory
      repositories = Repository.discover_all
      if repositories.empty?
        puts "Error: Not in a git repository"
        exit 1
      end

      primary_repo = repositories.first

      # Change to primary repo root for consistent paths
      Dir.chdir(primary_repo.root)

      model = Model.new(repositories)

      # Initialize Thread Pool
      @worker_queue = Queue.new
      @workers = POOL_SIZE.times.map do
        Thread.new do
          while (task = @worker_queue.pop)
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
            rescue StandardError
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
            Update.handle(model, msg) if msg
          end
        end
      end

      # After TUI exits, cd into last worktree if one was resumed
      if model.resume_to && model.resume_to.exists?
        Dir.chdir(model.resume_to.path)
        # OSC 7 tells terminal emulators (Ghostty, tmux, iTerm2) the CWD for new panes
        print "\e]7;file://localhost#{model.resume_to.path}\e\\"
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
        suspend_tui_and_run(cmd[:worktree], model, tui)
        Update.refresh_list(model)
        start_background_fetch(model, main_queue)
      end
    end

    def self.start_background_fetch(model, main_queue)
      # Increment generation to invalidate old results
      model.increment_generation
      current_gen = model.fetch_generation

      worktrees = model.worktrees

      # Batch fetch commit ages in background thread
      # Group by repository to fetch from correct git repo (avoids "bad object" errors)
      Thread.new do
        worktrees.group_by(&:repository).each do |repo, repo_worktrees|
          shas = repo_worktrees.map(&:sha).compact
          next if shas.empty?

          ages = Git.get_commit_ages(shas, repo_root: repo.root)

          repo_worktrees.each do |wt|
            if (age = ages[wt.sha])
              main_queue << {
                type: :update_commit_age,
                path: wt.path,
                age: age,
                generation: current_gen
              }
            end
          end
        end
      end

      # Queue Status Checks (Worker Pool)
      worktrees.each do |wt|
        @worker_queue << {
          type: :fetch_status,
          path: wt.path,
          result_queue: main_queue,
          generation: current_gen
        }
      end
    end

    def self.suspend_tui_and_run(worktree, model, tui)
      RatatuiRuby.restore_terminal

      puts "\e[H\e[2J" # Clear screen

      # Run setup if this is a new worktree
      if worktree.needs_setup?
        begin
          worktree.run_setup!(visible: true)
          worktree.mark_setup_complete!
        rescue Interrupt
          puts "\nSetup aborted."
          RatatuiRuby.init_terminal
          return
        end
      end

      puts "Launching claude in #{worktree.path}..."
      begin
        Dir.chdir(worktree.path) do
          if defined?(Bundler)
            Bundler.with_unbundled_env { system("claude") }
          else
            system("claude")
          end
        end
        # Track last resumed worktree for exit
        model.resume_to = worktree
      rescue StandardError => e
        puts "Error: #{e.message}"
        print "Press any key to return..."
        STDIN.getc
      ensure
        RatatuiRuby.init_terminal
      end
    end
  end
end
