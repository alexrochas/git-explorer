module GitExplorer
  class AnsiStyler
    CODES = {
      bold: 1,
      faint: 2,
      red: 31,
      green: 32,
      yellow: 33,
      blue: 34,
      magenta: 35,
      cyan: 36
    }.freeze

    def initialize(enabled:)
      @enabled = enabled
    end

    def enabled?
      @enabled
    end

    def apply(text, *styles)
      return text.to_s unless enabled?

      style_codes = styles.filter_map { |style| CODES[style] }
      return text.to_s if style_codes.empty?

      "\e[#{style_codes.join(';')}m#{text}\e[0m"
    end
  end
end
