namespace :faq do
  desc "Update the FAQ bot's search index from config/faq.yml (embeds new and edited questions)"
  task sync: :environment do
    result = FaqEntry.sync!
    puts "FAQ index: #{result[:total]} questions, #{result[:embedded]} embedded, #{result[:removed]} removed"
  end
end
