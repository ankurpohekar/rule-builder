require "test_helper"

class FaqApiTest < ActionDispatch::IntegrationTest
  setup { FaqEntry.sync!(embedder: Embedder.default) }

  test "lists the FAQ sections with keys" do
    get "/api/faqs"
    assert_response :success
    assert_equal "basics:0", response.parsed_body.first["items"].first["key"]
  end

  # Off-topic questions are answered without the LLM, so this runs end to end with no API key.
  test "an off-topic question is answered as not covered and logged" do
    post "/api/faq/ask", params: { question: "qwerty zxcvb" }, as: :json

    assert_response :success
    assert_equal false, response.parsed_body["answered"]
    assert_equal [], response.parsed_body["sources"]
    question = FaqQuestion.find(response.parsed_body["id"])
    assert_equal "qwerty zxcvb", question.question
    assert_not question.answered
    assert_equal 5, question.retrieved.size
  end

  test "a blank question is rejected" do
    post "/api/faq/ask", params: { question: " " }, as: :json
    assert_response :unprocessable_content
  end

  test "feedback is recorded and must be 1 or -1" do
    question = FaqQuestion.create!(question: "q", answer: "a")

    patch "/api/faq/questions/#{question.id}", params: { feedback: -1 }, as: :json
    assert_response :no_content
    assert_equal -1, question.reload.feedback

    patch "/api/faq/questions/#{question.id}", params: { feedback: 5 }, as: :json
    assert_response :unprocessable_content
  end
end
