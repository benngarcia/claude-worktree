# frozen_string_literal: true

require_relative '../claude/worktree/version'

module Cwt
  class View
    THEME = {
      header: { fg: :blue, modifiers: [:bold] },
      border: { fg: :dark_gray },
      selection: { fg: :black, bg: :blue },
      text: { fg: :white },
      dim: { fg: :dark_gray },
      accent: { fg: :cyan },
      dirty: { fg: :yellow },
      clean: { fg: :green },
      modal_border: { fg: :magenta },
      repo_header: { fg: :magenta, modifiers: [:bold] }
    }.freeze

    def self.draw(model, tui, frame)
      # Calculate actual item count: worktrees + repo headers + separators
      worktrees = model.visible_worktrees
      repo_count = worktrees.map(&:repository).uniq.size
      separator_count = [repo_count - 1, 0].max
      total_items = worktrees.size + repo_count + separator_count
      content_height = [total_items + 6, frame.area.height].min

      app_area = centered_app_area(tui, frame.area, width: 100, height: content_height)

      main_area, footer_area = tui.layout_split(
        app_area,
        direction: :vertical,
        constraints: [
          tui.constraint_fill(1),
          tui.constraint_length(4)
        ]
      )

      header_area, list_area = tui.layout_split(
        main_area,
        direction: :vertical,
        constraints: [
          tui.constraint_length(3),
          tui.constraint_fill(1)
        ]
      )

      draw_header(model, tui, frame, header_area)
      draw_list(model, tui, frame, list_area)
      draw_footer(model, tui, frame, footer_area)

      return unless model.mode == :creating

      draw_input_modal(model, tui, frame)
    end

    def self.centered_app_area(tui, area, width:, height:)
      w = [area.width, width].min
      h = [[area.height, height].min, 15].max
      h = [h, area.height].min

      x = area.x + (area.width - w) / 2
      y = area.y + (area.height - h) / 2

      tui.rect(x: x, y: y, width: w, height: h)
    end

    def self.draw_header(model, tui, frame, area)
      # Show repo count if multiple repos
      repo_info = if model.repositories.size > 1
        " (#{model.repositories.size} repos)"
      else
        ""
      end

      title = tui.paragraph(
        text: " CWT v#{Claude::Worktree::VERSION} • WORKTREE MANAGER#{repo_info} ",
        alignment: :center,
        style: tui.style(**THEME[:header]),
        block: tui.block(
          borders: [:bottom],
          border_style: tui.style(**THEME[:border])
        )
      )
      frame.render_widget(title, area)
    end

    def self.draw_list(model, tui, frame, area)
      items = []
      last_repo = nil
      worktree_to_visual = {}  # Map worktree index → visual index
      worktree_idx = 0

      model.visible_worktrees.each do |wt|
        # Add separator between repos (multi-repo view only)
        if model.repositories.size > 1 && wt.repository != last_repo
          if last_repo
            items << tui.text_line(spans: [
              tui.text_span(content: " ", style: tui.style(**THEME[:dim]))
            ])
          end
          last_repo = wt.repository
        end

        # Track visual position before adding worktree line
        worktree_to_visual[worktree_idx] = items.size
        worktree_idx += 1

        # Status Icons
        status_icon = wt.dirty ? '●' : ' '
        status_style = wt.dirty ? tui.style(**THEME[:dirty]) : tui.style(**THEME[:clean])

        time = wt.last_commit || ''

        if wt.main?
          # Main worktree (repo root) - selectable, magenta style with branch/time info
          indent = wt.repository.nested? ? "  " : ""
          items << tui.text_line(spans: [
            tui.text_span(content: " #{status_icon} ", style: status_style),
            tui.text_span(content: "#{indent}#{wt.repository.name}".ljust(25), style: tui.style(**THEME[:repo_header])),
            tui.text_span(content: (wt.branch || 'HEAD').ljust(25), style: tui.style(**THEME[:dim])),
            tui.text_span(content: time.rjust(15), style: tui.style(**THEME[:accent]))
          ])
        else
          # Regular worktree - extra indent, bold white
          indent = wt.repository.nested? ? "    " : "  "
          items << tui.text_line(spans: [
            tui.text_span(content: " #{status_icon} ", style: status_style),
            tui.text_span(content: "#{indent}#{wt.name}".ljust(25), style: tui.style(modifiers: [:bold])),
            tui.text_span(content: (wt.branch || 'HEAD').ljust(25), style: tui.style(**THEME[:dim])),
            tui.text_span(content: time.rjust(15), style: tui.style(**THEME[:accent]))
          ])
        end
      end

      # Convert worktree selection index to visual index
      visual_index = worktree_to_visual[model.selection_index] || 0

      # Dynamic Title based on context
      title_content = if model.mode == :filtering
                        tui.text_line(spans: [
                          tui.text_span(content: ' FILTERING: ', style: tui.style(**THEME[:accent])),
                          tui.text_span(content: model.filter_query,
                                        style: tui.style(
                                          fg: :white, modifiers: [:bold]
                                        ))
                        ])
                      elsif model.repositories.size > 1 && model.show_all_repos
                        tui.text_line(spans: [
                          tui.text_span(content: ' ALL SESSIONS ', style: tui.style(**THEME[:dim])),
                          tui.text_span(content: '(t: toggle)', style: tui.style(**THEME[:accent]))
                        ])
                      else
                        tui.text_line(spans: [tui.text_span(content: ' SESSIONS ', style: tui.style(**THEME[:dim]))])
                      end

      list = tui.list(
        items: items,
        selected_index: visual_index,
        highlight_style: tui.style(**THEME[:selection]),
        highlight_symbol: '▎',
        block: tui.block(
          titles: [{ content: title_content }],
          borders: [:all],
          border_style: tui.style(**THEME[:border])
        )
      )

      frame.render_widget(list, area)
    end

    def self.draw_footer(model, tui, frame, area)
      keys = []

      add_key = lambda { |key, desc|
        keys << tui.text_span(content: " ", style: tui.style(**THEME[:dim]))
        keys << tui.text_span(content: " #{key}", style: tui.style(bg: :dark_gray, fg: :white))
        keys << tui.text_span(content: "  #{desc} ", style: tui.style(**THEME[:dim]))
      }

      case model.mode
      when :creating
        add_key.call('Enter', 'Confirm')
        add_key.call('Tab', 'Change Repo')
        add_key.call('Esc', 'Cancel')
      when :filtering
        add_key.call('Type', 'Search')
        add_key.call('Enter', 'Select')
        add_key.call('Esc', 'Reset')
      else
        add_key.call('n', 'New')
        add_key.call('/', 'Filter')
        add_key.call('Enter', 'Resume')
        add_key.call('d', 'Delete')
        if model.repositories.size > 1
          add_key.call('t', 'Toggle')
        end
        add_key.call('q', 'Quit')
      end

      msg_style = if model.message.downcase.include?('error') || model.message.downcase.include?('warning')
                    tui.style(fg: :red, modifiers: [:bold])
                  else
                    tui.style(**THEME[:accent])
                  end

      text = [
        tui.text_line(spans: [tui.text_span(content: model.message, style: msg_style)]),
        tui.text_line(spans: []),
        tui.text_line(spans: keys)
      ]

      footer = tui.paragraph(
        text: text,
        block: tui.block(
          borders: [:top],
          border_style: tui.style(**THEME[:border])
        )
      )

      frame.render_widget(footer, area)
    end

    def self.draw_input_modal(model, tui, frame)
      area = center_rect(tui, frame.area, 50, 5)

      frame.render_widget(tui.clear, area)

      # Show target repository in title when multiple repos
      target_repo = model.target_repository
      title_text = if model.repositories.size > 1
        " NEW SESSION in #{target_repo.name} "
      else
        ' NEW SESSION '
      end

      # Add cursor indicator to input
      input_with_cursor = "#{model.input_buffer}|"

      input = tui.paragraph(
        text: input_with_cursor,
        style: tui.style(fg: :white),
        block: tui.block(
          title: title_text,
          title_style: tui.style(fg: :blue, modifiers: [:bold]),
          borders: [:all],
          border_style: tui.style(**THEME[:modal_border])
        )
      )

      frame.render_widget(input, area)
    end

    def self.center_rect(tui, area, width_percent, height_len)
      vert = tui.layout_split(
        area,
        direction: :vertical,
        constraints: [
          tui.constraint_percentage((100 - 10) / 2),
          tui.constraint_length(height_len),
          tui.constraint_min(0)
        ]
      )

      horiz = tui.layout_split(
        vert[1],
        direction: :horizontal,
        constraints: [
          tui.constraint_percentage((100 - width_percent) / 2),
          tui.constraint_percentage(width_percent),
          tui.constraint_min(0)
        ]
      )

      horiz[1]
    end
  end
end
