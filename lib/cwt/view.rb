# frozen_string_literal: true

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
      modal_border: { fg: :magenta }
    }.freeze

    def self.draw(model, tui, frame)
      # 1. Calculate App Area (Centered, Max Width/Height)
      # Use full height but constrained width? Or constrained height too?
      # User said "Keybindings section is so far...".
      # If I have 3 items on a 60 row terminal, the footer is at row 60.
      # I should shrink the height to fit content if possible.
      
      content_height = [model.visible_worktrees.size + 6, frame.area.height].min
      # +6 accounts for Header(3) + Footer(3).
      
      # Let's enforce a minimum width/height for usability
      app_area = centered_app_area(tui, frame.area, width: 100, height: content_height)

      main_area, footer_area = tui.layout_split(
        app_area,
        direction: :vertical,
        constraints: [
          tui.constraint_fill(1),
          tui.constraint_length(3)
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

      draw_header(tui, frame, header_area)
      draw_list(model, tui, frame, list_area)
      draw_footer(model, tui, frame, footer_area)

      if model.mode == :creating
        draw_input_modal(model, tui, frame)
      end
    end

    def self.centered_app_area(tui, area, width:, height:)
       # Calculate width
       w = [area.width, width].min
       
       # Calculate height (min 15 lines to avoid jarring jumps)
       h = [[area.height, height].min, 15].max
       h = [h, area.height].min # Ensure we don't exceed terminal
       
       # Center it
       x = area.x + (area.width - w) / 2
       y = area.y + (area.height - h) / 2
       
       tui.rect(x: x, y: y, width: w, height: h)
    end

    def self.draw_header(tui, frame, area)
      # Modern, minimalist header
      title = tui.paragraph(
        text: " CWT • WORKTREE MANAGER ",
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
      items = model.visible_worktrees.map do |wt|
        name = File.basename(wt[:path])
        branch = wt[:branch] || "HEAD"
        
        # Status Icons
        # Using simple unicode that is generally supported
        status_icon = wt[:dirty] ? "●" : " " 
        status_style = wt[:dirty] ? tui.style(**THEME[:dirty]) : tui.style(**THEME[:clean])
        
        time = wt[:last_commit] || ""
        
        # Consistent Column Widths
        # Name: 25, Branch: 25, Time: 15, Status: 2
        
        tui.text_line(spans: [
          tui.text_span(content: " #{status_icon} ", style: status_style),
          tui.text_span(content: name.ljust(25), style: tui.style(modifiers: [:bold])),
          tui.text_span(content: branch.ljust(25), style: tui.style(**THEME[:dim])),
          tui.text_span(content: time.rjust(15), style: tui.style(**THEME[:accent]))
        ])
      end

      # Dynamic Title based on context
      title_content = if model.mode == :filtering
                        tui.text_line(spans: [
                          tui.text_span(content: " FILTERING: ", style: tui.style(**THEME[:accent])),
                          tui.text_span(content: model.filter_query, style: tui.style(fg: :white, modifiers: [:bold]))
                        ])
                      else
                        tui.text_line(spans: [tui.text_span(content: " SESSIONS ", style: tui.style(**THEME[:dim]))])
                      end

      list = tui.list(
        items: items,
        selected_index: model.selection_index,
        highlight_style: tui.style(**THEME[:selection]),
        highlight_symbol: "▎", # Modern block cursor
        block: tui.block(
          titles: [ { content: title_content } ],
          borders: [:all],
          border_style: tui.style(**THEME[:border])
        )
      )
      
      frame.render_widget(list, area)
    end

    def self.draw_footer(model, tui, frame, area)
      keys = []
      
      # Helper to build consistent key hints
      add_key = ->(key, desc) {
        keys << tui.text_span(content: " #{key} ", style: tui.style(bg: :dark_gray, fg: :white))
        keys << tui.text_span(content: " #{desc} ", style: tui.style(**THEME[:dim]))
      }

      case model.mode
      when :creating
        add_key.call("Enter", "Confirm")
        add_key.call("Esc", "Cancel")
      when :filtering
        add_key.call("Type", "Search")
        add_key.call("Enter", "Select")
        add_key.call("Esc", "Reset")
      else
        add_key.call("n", "New")
        add_key.call("/", "Filter")
        add_key.call("Enter", "Resume")
        add_key.call("d", "Delete")
        add_key.call("q", "Quit")
      end

      # Status Message on the right (if we calculate length, but Paragraph handles simple text)
      # We'll put message on top line, keys on bottom line of the footer block?
      # Or just inline them.
      
      # Let's do: Message .... [Keys]
      # But Ratatui Paragraph is simple.
      
      # Actually, let's just render the keys. The message is overlayed or separate.
      # The previous implementation combined them.
      
      # Let's put the message in the title of the footer, and keys in the body?
      # Or Message left, keys right?
      
      # Simple approach: Line 1: Message (highlighted if warning). Line 2: Keys.
      
      msg_style = model.message.downcase.include?("error") || model.message.downcase.include?("warning") ? 
                  tui.style(fg: :red, modifiers: [:bold]) : 
                  tui.style(**THEME[:accent])

      text = [
        tui.text_line(spans: [tui.text_span(content: model.message, style: msg_style)]),
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
      area = center_rect(tui, frame.area, 50, 3)
      
      # Create a "shadow" or clear background
      frame.render_widget(tui.clear, area)
      
      input = tui.paragraph(
        text: model.input_buffer,
        style: tui.style(fg: :white),
        block: tui.block(
          title: " NEW SESSION ",
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