# frozen_string_literal: true

RSpec.describe Cosmo::API::Cron::Describer do
  {
    "* * * * *" => "Every minute",
    "* * * * * *" => "Every second",
    "*/5 * * * *" => "At every 5th minute",
    "30 9 * * *" => "At 09:30",
    "0 0 9 * * *" => "At 09:00",
    "5 30 9 * * *" => "At 09:30:05",
    "0 * * * *" => "At minute 0",
    "15,45 * * * *" => "At minute 15 and 45",
    "0 */2 * * *" => "At minute 0 past every 2nd hour",
    "0 9-17 * * *" => "At minute 0 past every hour from 9 through 17",
    "* 9 * * *" => "At every minute past hour 9",
    "*/10 * * * * *" => "At every 10th second, every minute",
    "0 9 * * 1-5" => "At 09:00 on every day-of-week from Monday through Friday",
    "0 9 * * MON,FRI" => "At 09:00 on Monday and Friday",
    "0 9 * * 7" => "At 09:00 on Sunday",
    "0 0 1 * *" => "At 00:00 on day-of-month 1",
    "0 0 1,15 * *" => "At 00:00 on day-of-month 1 and 15",
    "0 0 1 * MON" => "At 00:00 on day-of-month 1 and on Monday",
    "0 0 1 jan *" => "At 00:00 on day-of-month 1 in January",
    "0 0 * 1-3 *" => "At 00:00 in every month from January through March",
    "0 0 */3 * *" => "At 00:00 on every 3rd day-of-month",
    "@hourly" => "At minute 0",
    "@daily" => "At 00:00",
    "@weekly" => "At 00:00 on Sunday",
    "@monthly" => "At 00:00 on day-of-month 1",
    "@yearly" => "At 00:00 on day-of-month 1 in January",
    "@every 5m" => "Every 5 minutes",
    "@every 1h" => "Every hour",
    "@every 1h30m" => "Every 1 hour and 30 minutes",
    "@every 90s" => "Every 90 seconds",
    "@at 2027-01-01T00:00:00Z" => "Once at 2027-01-01T00:00:00Z"
  }.each do |expression, description|
    it "describes #{expression.inspect}" do
      expect(described_class.call(expression)).to eq(description)
    end
  end

  [
    nil, "", "   ", "nonsense", "* * *", "* * * * * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * * 13 *",
    "* * * * 8", "5-2 * * * *", "*/0 * * * *", "*-5 * * * *", "a,b * * * *", ", * * * *", "1,,2 * * * *",
    "* * * FOO *", "@every", "@every soon", "@every 0s", "@every 5x", "@at tomorrow", "@sometimes", "L * * * *",
    "0 0 L * *", "1-2-3 * * * *", "1/ * * * *"
  ].each do |expression|
    it "returns an empty string for #{expression.inspect}" do
      expect(described_class.call(expression)).to eq("")
    end
  end
end
