# Lower priority numbers are checked first; the first matching rule decides the status.
rules = [
  {
    name: "Reject low credit", priority: 10, outcome: "rejected",
    description: "Credit score below 550 is an automatic reject.",
    conditions: { combinator: "all", conditions: [
      { field: "credit_score", operator: "lt", value: 550 }
    ] }
  },
  {
    name: "Reject minors", priority: 20, outcome: "rejected",
    conditions: { combinator: "all", conditions: [
      { field: "age", operator: "lt", value: 18 }
    ] }
  },
  {
    name: "Approve strong profile", priority: 30, outcome: "approved",
    description: "Good credit and steady income.",
    conditions: { combinator: "all", conditions: [
      { field: "credit_score", operator: "gte", value: 700 },
      { field: "annual_income", operator: "gte", value: 50000 },
      { combinator: "any", conditions: [
        { field: "employment_status", operator: "in", value: %w[employed self_employed] },
        { field: "annual_income", operator: "gte", value: 150000 }
      ] }
    ] }
  }
]

rules.each do |attrs|
  Rule.find_or_initialize_by(name: attrs[:name]).update!(attrs)
end

[
  { name: "Asha Rao",     email: "asha@example.com",  age: 34, credit_score: 760, annual_income: 92000,  employment_status: "employed",      country: "IN" },
  { name: "Ben Carter",   email: "ben@example.com",   age: 29, credit_score: 520, annual_income: 61000,  employment_status: "employed",      country: "US" },
  { name: "Chen Wei",     email: "chen@example.com",  age: 17, credit_score: 680, annual_income: 8000,   employment_status: "student",       country: "SG" },
  { name: "Diana Lopez",  email: "diana@example.com", age: 45, credit_score: 710, annual_income: 48000,  employment_status: "self_employed", country: "MX" },
  { name: "Elif Demir",   email: "elif@example.com",  age: 52, credit_score: 805, annual_income: 210000, employment_status: "retired",       country: "TR" },
  { name: "Farah Khan",   email: "farah@example.com", age: 38, credit_score: 640, annual_income: 75000,  employment_status: "employed",      country: "PK" }
].each do |attrs|
  Applicant.find_or_initialize_by(email: attrs[:email]).update!(attrs)
end
