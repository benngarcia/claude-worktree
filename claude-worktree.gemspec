# frozen_string_literal: true

require_relative 'lib/claude/worktree/version'

Gem::Specification.new do |spec|
  spec.name = 'claude-worktree'
  spec.version = Claude::Worktree::VERSION
  spec.authors = ['Ben Garcia']
  spec.email = ['hey@bengarcia.dev']

  spec.summary = 'A TUI tool to manage Git Worktrees for AI coding agents.'
  spec.description = 'Manages git worktrees for Claude Code sessions.'
  spec.homepage = 'https://github.com/bengarcia/claude-worktree'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/bengarcia/claude-worktree'
  spec.metadata['changelog_uri'] = 'https://github.com/bengarcia/claude-worktree/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/])
    end
  end
  spec.bindir = 'exe'
  spec.executables = ['cwt']
  spec.require_paths = ['lib']

  spec.add_dependency 'ratatui_ruby'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
