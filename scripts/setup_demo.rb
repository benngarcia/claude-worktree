#!/usr/bin/env ruby
require 'fileutils'
require 'open3'

# Configuration
DEMO_DIR = "cwt_demo_repo"
WORKTREES_DIR = ".worktrees"

# Funny session names (The Prototyper's chaos)
SESSIONS = [
  "feature/add-lasers-to-ui",
  "fix/undefined-is-not-a-function-again",
  "chore/upgrade-everything-yolo",
  "experiment/rewrite-in-assembly",
  "refactor/rename-all-variables-to-emoji",
  "feature/dark-mode-for-logs",
  "bug/why-is-production-down",
  "wip/ai-will-fix-it-eventually",
]

def run(cmd)
  stdout, stderr, status = Open3.capture3(cmd)
  unless status.success?
    puts "Error running: #{cmd}"
    puts stderr
    exit 1
  end
  stdout
end

puts "🚀 Setting up CWT Demo Environment..."

# 1. Create and Init Repo
if Dir.exist?(DEMO_DIR)
  puts "Cleaning up old demo..."
  FileUtils.rm_rf(DEMO_DIR)
end
FileUtils.mkdir_p(DEMO_DIR)
Dir.chdir(DEMO_DIR)

puts "📦 Initializing git repo..."
run "git init"
run "git config user.email 'demo@example.com'"
run "git config user.name 'Demo User'"
run "touch README.md"
run "git add README.md"
run "git commit -m 'Initial commit'"

# 2. Create Worktrees
puts "🌳 Spawning worktrees..."
SESSIONS.each do |session|
  # Create branch and worktree
  path = File.join(WORKTREES_DIR, session.gsub('/', '-'))
  run "git worktree add -b #{session} #{path}"
  
  # Add some "dirty" state to random sessions
  if rand < 0.4
    puts "   - Making #{session} dirty..."
    File.write(File.join(path, "dirty_file.txt"), "This is uncommitted work")
  end
end

# 3. Create a fake .env to show off symlinking
File.write(".env", "SECRET_KEY=12345\nAPI_HOST=localhost:3000")
File.write("node_modules", "fake_node_modules") # Just a file for demo

puts "\n✨ Demo Ready!"
puts "To run the demo:"
puts "  cd #{DEMO_DIR}"
puts "  cwt"
