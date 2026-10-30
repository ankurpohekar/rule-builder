require "test_helper"

class FaqTest < ActiveSupport::TestCase
  test "every item has a stable key made of its section and position" do
    assert_equal "basics:0", Faq.items.first.key
    assert_equal Faq.items.size, Faq.items.map(&:key).uniq.size
    assert_equal "Can I delete an applicant?", Faq.find("applicants:7").question
    assert_nil Faq.find("nope:0")
  end

  test "sections carry the keys the page uses to link questions" do
    keys = Faq.sections.flat_map { |section| section["items"].map { |item| item["key"] } }
    assert_equal Faq.items.map(&:key), keys
  end
end
