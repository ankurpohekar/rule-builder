# Takes applicant input from the API, cleans it up, checks it, and saves the Applicant.
#
# The split of responsibilities:
# - Applicant (model) keeps rules that must hold however a record is written: required
#   fields, unique email, allowed statuses.
# - ApplicantForm owns input concerns: normalizing what people type, and limits that only
#   make sense for submitted data (realistic age, credit score range, country code format).
#
#   form = ApplicantForm.new(params, applicant: Applicant.new)  # or an existing applicant
#   form.save  # => true/false; on false, form.errors has form and model errors together
class ApplicantForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Typed attributes cast junk like "abc" to 0 for integers. Numericality validations check
  # the raw input instead when an `<attr>_before_type_cast` reader exists, so provide one
  # (ActiveRecord models have it built in; ActiveModel::Attributes does not).
  attribute_method_suffix "_before_type_cast", parameters: false

  attribute :name, :string
  attribute :email, :string
  attribute :age, :integer
  attribute :credit_score, :integer
  attribute :annual_income, :decimal
  attribute :employment_status, :string
  attribute :country, :string

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :age, numericality: { only_integer: true, in: 0..120 }, allow_nil: true
  validates :credit_score, numericality: { only_integer: true, in: 300..850 }, allow_nil: true
  validates :annual_income, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :employment_status, inclusion: { in: Applicant::EMPLOYMENT_STATUSES }, allow_nil: true
  validates :country, format: { with: /\A[A-Z]{2}\z/, message: "must be a 2-letter code like US" }, allow_nil: true

  attr_reader :applicant

  # Starts from the applicant's current values, so an update that sends only some fields
  # is still validated as a whole record.
  def initialize(params = {}, applicant: Applicant.new)
    @applicant = applicant
    super(applicant.attributes.slice(*self.class.attribute_names).merge(params.to_h))
  end

  def save
    return false unless valid?

    applicant.assign_attributes(attributes)
    return true if applicant.save

    # Model-level failures (e.g. email already taken) surface on the form too.
    errors.merge!(applicant.errors)
    false
  end

  private def attribute_before_type_cast(name)
    @attributes[name].value_before_type_cast
  end

  # Normalize as values are assigned, so validations and the model see the clean version.
  def name=(value)
    super(value.to_s.squish.presence)
  end

  def email=(value)
    super(value.to_s.strip.downcase.presence)
  end

  def country=(value)
    super(value.to_s.strip.upcase.presence)
  end

  def employment_status=(value)
    super(value.to_s.strip.presence)
  end
end
