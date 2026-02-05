# frozen_string_literal: true

require 'json'

module Cwt
  class Config
    DEFAULT_SYMLINKS = [
      { "name" => ".claude", "strategy" => "nearest" },
      { "name" => ".mcp.json", "strategy" => "nearest" },
      { "name" => "CLAUDE.md", "strategy" => "nearest" },
      { "name" => "node_modules", "strategy" => "local" },
      { "name" => ".cwt", "strategy" => "parent" },
      { "name" => ".env", "strategy" => "local" },
      { "name" => ".envrc", "strategy" => "local" }
    ].freeze

    attr_reader :path, :data

    def initialize(repo_root)
      @path = File.join(repo_root, ".cwt", "config.json")
      @data = load_config
    end

    def symlinks
      @data.dig("symlinks", "items") || DEFAULT_SYMLINKS
    end

    def strategy_for(item)
      found = symlinks.find { |s| s["name"] == item }
      found&.dig("strategy") || "nearest"
    end

    def nested_repo_paths
      @data.dig("nested_repos", "paths") || []
    end

    def auto_discover_nested?
      @data.dig("nested_repos", "auto_discover") != false
    end

    private

    def load_config
      return {} unless File.exist?(@path)

      JSON.parse(File.read(@path))
    rescue JSON::ParserError => e
      warn "Warning: Failed to parse #{@path}: #{e.message}"
      {}
    end
  end
end
