# frozen_string_literal: true

require "test_helper"
require "cwt/model"

module Cwt
  class TestModel < Minitest::Test
    def setup
      @model = Model.new
    end

    def test_initialization
      assert_equal [], @model.worktrees
      assert_equal 0, @model.selection_index
      assert_equal :normal, @model.mode
      assert @model.running
    end

    def test_update_worktrees
      list = [{ path: "a" }, { path: "b" }]
      @model.update_worktrees(list)
      assert_equal list, @model.worktrees
    end

    def test_move_selection
      @model.update_worktrees([{ path: "a" }, { path: "b" }, { path: "c" }])
      @model.move_selection(1)
      assert_equal 1, @model.selection_index
      @model.move_selection(1)
      assert_equal 2, @model.selection_index
      @model.move_selection(1) # Boundary
      assert_equal 2, @model.selection_index
      @model.move_selection(-1)
      assert_equal 1, @model.selection_index
    end

    def test_input_handling
      @model.set_mode(:creating)
      @model.input_append("a")
      @model.input_append("b")
      assert_equal "ab", @model.input_buffer
      @model.input_backspace
      assert_equal "a", @model.input_buffer
    end
  end
end
