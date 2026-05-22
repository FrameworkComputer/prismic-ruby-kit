module Prismic
  module Fragments
    class StructuredText < Fragment
      class BlockGroup
        attr_reader :kind, :blocks

        def initialize(kind)
          @kind = kind
          @blocks = []
        end

        def <<(block)
          blocks << block
        end
      end

      attr_accessor :blocks

      def initialize(blocks)
        @blocks = blocks
      end

      def as_html(link_resolver, html_serializer = nil)
        groups = []
        last = nil
        blocks.each do |block|
          group = if block.is_a?(Block::ListItem)
                    block.ordered? ? 'ol' : 'ul'
                  end
          groups << BlockGroup.new(group) if !last || group != last
          groups.last << block
          last = group
        end

        result = String.new
        groups.each_with_index do |group, i|
          result << "\n\n" if i > 0
          case group.kind
          when 'ol'
            result << '<ol>'
            group.blocks.each { |b| result << b.as_html(link_resolver, html_serializer) }
            result << '</ol>'
          when 'ul'
            result << '<ul>'
            group.blocks.each { |b| result << b.as_html(link_resolver, html_serializer) }
            result << '</ul>'
          else
            group.blocks.each { |b| result << b.as_html(link_resolver, html_serializer) }
          end
        end
        result
      end

      def as_text(separator = ' ')
        blocks.map { |block| block.as_text }.compact.join(separator)
      end

      def first_title
        max_level = 6
        title = false
        @blocks.each do |block|
          if block.is_a?(Prismic::Fragments::StructuredText::Block::Heading) && (block.level < max_level)
            title = block.text
            max_level = block.level
          end
        end
        title
      end

      class Span
        attr_accessor :start, :end

        def initialize(start, finish)
          @start = start
          @end = finish
        end

        class Label < Span
          attr_accessor :label

          def initialize(start, finish, label)
            super(start, finish)
            @label = label
          end

          def serialize(text, _link_resolver = nil)
            "<span class=\"#{@label}\">#{text}</span>"
          end
        end

        class Em < Span
          def serialize(text, _link_resolver = nil)
            "<em>#{text}</em>"
          end
        end

        class Strong < Span
          def serialize(text, _link_resolver = nil)
            "<strong>#{text}</strong>"
          end
        end

        class Hyperlink < Span
          attr_accessor :link

          def initialize(start, finish, link)
            super(start, finish)
            @link = link
          end

          def serialize(text, link_resolver = nil)
            if link.is_a? Prismic::Fragments::DocumentLink and link.broken
              "<span>#{text}</span>"
            elsif !link.target.nil?
              %(<a href="#{link.url(link_resolver)}" target="#{link.target}" rel="noopener">#{text}</a>)
            else
              %(<a href="#{link.url(link_resolver)}">#{text}</a>)
            end
          end
        end
      end

      class Block
        def as_text
          nil
        end

        class Text
          ESCAPE_MAP = {
            "'" => '&#39;',
            '&' => '&amp;',
            '"' => '&quot;',
            '<' => '&lt;',
            '>' => '&gt;'
          }.freeze
          ESCAPE_PATTERN = /['&"<>]/.freeze

          attr_accessor :text, :spans, :label

          def initialize(text, spans, label = nil)
            @text = text
            @spans = spans.select { |span| span.start < span.end }
            @label = label
          end

          def class_code
            (@label && %( class="#{label}")) || ''
          end

          def as_html(link_resolver = nil, html_serializer = nil)
            start_spans, end_spans = prepare_spans
            boundaries = boundary_positions
            html = String.new
            stack = []
            last_idx = boundaries.length - 1

            boundaries.each_with_index do |pos, idx|
              if (ending = end_spans[pos])
                ending.each do
                  tag = stack.pop
                  inner = serialize(tag[:span], tag[:html], link_resolver, html_serializer)
                  if stack.empty?
                    html << inner
                  else
                    stack[-1][:html] << inner
                  end
                end
              end

              if (starting = start_spans[pos])
                starting.each do |span|
                  stack.push(span: span, html: String.new)
                end
              end

              break if idx == last_idx

              next_pos = boundaries[idx + 1]
              next if pos == next_pos

              escaped = cgi_escape_html(text[pos...next_pos])
              if stack.empty?
                html << escaped
              else
                stack[-1][:html] << escaped
              end
            end

            html.gsub!("\n", '<br>')
            html
          end

          def cgi_escape_html(string)
            string.gsub(ESCAPE_PATTERN, ESCAPE_MAP)
          end

          def prepare_spans
            return [@start_spans, @end_spans] if @prepared_spans

            start_spans = Hash.new { |h, k| h[k] = [] }
            end_spans = Hash.new { |h, k| h[k] = [] }
            spans.each do |span|
              start_spans[span.start] << span
              end_spans[span.end] << span
            end
            start_spans.each_value { |s| s.sort! { |a, b| (b.end - b.start) <=> (a.end - a.start) } }

            @start_spans = start_spans
            @end_spans = end_spans
            @prepared_spans = true
            [@start_spans, @end_spans]
          end

          def as_text
            @text
          end

          def serialize(elt, text, link_resolver, html_serializer)
            custom_html = html_serializer && html_serializer.serialize(elt, text)
            custom_html.nil? ? elt.serialize(text, link_resolver) : custom_html
          end

          private :class_code, :cgi_escape_html

          private

          def boundary_positions
            positions = [0, text.length]
            spans.each do |span|
              positions << span.start
              positions << span.end
            end
            positions.uniq!
            positions.sort!
            positions
          end
        end

        class Heading < Text
          attr_accessor :level

          def initialize(text, spans, level, label = nil)
            super(text, spans, label)
            @level = level
          end

          def as_html(link_resolver = nil, html_serializer = nil)
            custom_html = html_serializer && html_serializer.serialize(self, super)
            if custom_html.nil?
              %(<h#{level}#{class_code}>#{super}</h#{level}>)
            else
              custom_html
            end
          end
        end

        class Paragraph < Text
          def as_html(link_resolver = nil, html_serializer = nil)
            custom_html = html_serializer && html_serializer.serialize(self, super)
            if custom_html.nil?
              %(<p#{class_code}>#{super}</p>)
            else
              custom_html
            end
          end
        end

        class Preformatted < Text
          def as_html(link_resolver = nil, html_serializer = nil)
            custom_html = html_serializer && html_serializer.serialize(self, super)
            if custom_html.nil?
              %(<pre#{class_code}>#{super}</pre>)
            else
              custom_html
            end
          end
        end

        class ListItem < Text
          attr_accessor :ordered
          alias ordered? ordered

          def initialize(text, spans, ordered, label = nil)
            super(text, spans, label)
            @ordered = ordered
          end

          def as_html(link_resolver, html_serializer = nil)
            custom_html = html_serializer && html_serializer.serialize(self, super)
            if custom_html.nil?
              %(<li#{class_code}>#{super}</li>)
            else
              custom_html
            end
          end
        end

        class Image < Block
          attr_accessor :view, :label

          def initialize(view, label = nil)
            @view = view
            @label = label
          end

          def url
            @view.url
          end

          def width
            @view.width
          end

          def height
            @view.height
          end

          def alt
            @view.alt
          end

          def copyright
            @view.copyright
          end

          def link_to
            @view.link_to
          end

          def as_html(link_resolver, html_serializer = nil)
            custom = html_serializer && html_serializer.serialize(self, '')
            return custom unless custom.nil?

            if @label.nil?
              %(<p class="block-img">#{view.as_html(link_resolver)}</p>)
            else
              %(<p class="block-img #{@label}">#{view.as_html(link_resolver)}</p>)
            end
          end
        end

        class Embed < Block
          attr_accessor :embed, :label

          def initialize(embed, label)
            @embed = embed
            @label = label
          end

          def embed_type
            @embed.embed_type
          end

          def provider
            @embed.provider
          end

          def url
            @embed.url
          end

          def html
            @embed.html
          end

          def as_html(link_resolver, html_serializer = nil)
            custom = html_serializer && html_serializer.serialize(self, '')
            custom.nil? ? embed.as_html(link_resolver) : custom
          end
        end
      end
    end
  end
end
