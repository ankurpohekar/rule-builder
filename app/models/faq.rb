# Reads the FAQ content from config/faq.yml, the single source for the FAQ page and the bot.
#
#   Faq.sections        # => [{ "id" => "basics", "title" => "Getting started", "items" => [...] }, ...]
#   Faq.items           # => [#<Faq::Item key="basics:0" question="What is Rule Builder?" ...>, ...]
#   Faq.find("rules:2") # => #<Faq::Item ...> or nil
module Faq
  PATH = Rails.root.join("config/faq.yml")

  Item = Data.define(:key, :section_id, :section_title, :question, :answer) do
    # The text that gets embedded and keyword-searched: the question gives the topic,
    # the answer gives the vocabulary people use when they ask.
    def content = "#{question}\n#{answer}"
  end

  class << self
    def sections
      load.fetch(:sections)
    end

    def items
      load.fetch(:items)
    end

    def find(key)
      load.fetch(:by_key)[key]
    end

    # Clears the cached file, e.g. after editing it in a running console.
    def reload!
      @load = nil
    end

    private
      def load
        @load = nil if Rails.env.local? && @loaded_mtime != PATH.mtime
        @load ||= begin
          @loaded_mtime = PATH.mtime
          sections = YAML.load_file(PATH).map do |section|
            items = section["items"].each_with_index.map { |item, i| item.merge("key" => "#{section['id']}:#{i}") }
            section.merge("items" => items)
          end
          items = sections.flat_map do |section|
            section["items"].map do |item|
              Item.new(key: item["key"], section_id: section["id"], section_title: section["title"],
                       question: item["q"], answer: item["a"])
            end
          end
          { sections: sections, items: items, by_key: items.index_by(&:key) }
        end
      end
  end
end
