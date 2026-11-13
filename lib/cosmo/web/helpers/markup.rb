# frozen_string_literal: true

module Cosmo
  class Web
    module Helpers
      # Renders user-supplied text that may carry a little HTML, such as a batch description.
      module Markup
        TAG = %r{<(/?)([a-z]+)((?:\s+[^<>]*)?)>}i
        TAGS = %w[a b i em strong code br].freeze
        HREF = /\A\s+href\s*=\s*(?:"([^"]*)"|'([^']*)')\s*\z/i
        URL = %r{\Ahttps?://}i

        # Keeps +a+ (http/https +href+ only), +b+, +i+, +em+, +strong+, +code+ and +br+, and escapes every other tag and
        # attribute, so a description can link out but never run script.
        #
        # @param text [String, nil]
        # @return [String] the HTML
        def description_html(text)
          out = +""
          rest = text.to_s
          while (m = TAG.match(rest))
            out << h(m.pre_match) << tag_html(m)
            rest = m.post_match
          end
          out << h(rest)
        end

        private

        def tag_html(match)
          name = match[2].downcase
          return h(match[0]) unless TAGS.include?(name)
          return "</#{name}>" if match[1] == "/"
          return "<#{name}>" if match[3].strip.empty?

          name == "a" ? link_html(match) : h(match[0])
        end

        def link_html(match)
          href = HREF.match(match[3])&.then { |m| m[1] || m[2] }
          return h(match[0]) unless href&.match?(URL)

          %(<a href="#{h(href)}" target="_blank" rel="noopener noreferrer">)
        end
      end
    end
  end
end
