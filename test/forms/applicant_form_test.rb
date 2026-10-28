require "test_helper"

class ApplicantFormTest < ActiveSupport::TestCase
  def valid_params(**overrides)
    { name: "Asha Rao", email: "asha@example.com" }.merge(overrides)
  end

  test "normalizes input before validating and saving" do
    form = ApplicantForm.new(valid_params(name: "  Asha   Rao ", email: " Asha@Example.COM ", country: " in ", employment_status: ""))
    assert form.save

    applicant = form.applicant.reload
    assert_equal "Asha Rao", applicant.name
    assert_equal "asha@example.com", applicant.email
    assert_equal "IN", applicant.country
    assert_nil applicant.employment_status
  end

  test "casts form input to typed values" do
    form = ApplicantForm.new(valid_params(age: "34", credit_score: "720", annual_income: "52000.50"))
    assert form.save
    assert_equal [ 34, 720, BigDecimal("52000.50") ], form.applicant.values_at(:age, :credit_score, :annual_income)
  end

  test "rejects non-numeric input instead of casting it to zero" do
    form = ApplicantForm.new(valid_params(age: "abc", credit_score: "7x0"))
    assert_not form.save
    assert_includes form.errors[:age], "is not a number"
    assert_includes form.errors[:credit_score], "is not a number"
    assert_not form.applicant.persisted?
  end

  test "enforces input limits the model does not" do
    form = ApplicantForm.new(valid_params(age: 130, credit_score: 200, country: "USA", email: "not-an-email"))
    assert_not form.valid?
    assert_equal %i[age country credit_score email], form.errors.attribute_names.sort
  end

  test "surfaces model errors such as a duplicate email" do
    Applicant.create!(name: "First", email: "asha@example.com")

    form = ApplicantForm.new(valid_params(email: "ASHA@example.com"))
    assert_not form.save
    assert_includes form.errors.full_messages, "Email has already been taken"
  end

  test "partial update keeps existing values and validates the whole record" do
    applicant = Applicant.create!(name: "Asha Rao", email: "asha@example.com", age: 34, country: "IN")

    form = ApplicantForm.new({ credit_score: "760" }, applicant: applicant)
    assert form.save
    assert_equal [ "Asha Rao", 34, 760, "IN" ], applicant.reload.values_at(:name, :age, :credit_score, :country)

    assert_not ApplicantForm.new({ age: "200" }, applicant: applicant).save
    assert_equal 34, applicant.reload.age
  end

  test "saving through the form still runs the rules" do
    Rule.create!(name: "Approve good credit", outcome: "approved", priority: 1,
      conditions: { combinator: "all", conditions: [ { field: "credit_score", operator: "gte", value: 700 } ] })

    form = ApplicantForm.new(valid_params(credit_score: "720"))
    assert form.save
    assert_equal "approved", form.applicant.status
  end
end
