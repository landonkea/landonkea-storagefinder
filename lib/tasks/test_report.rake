# This rake task runs the test suite and RuboCop, then writes a single
# markdown summary (pass/fail counts, failures, rubocop offense count,
# timestamp) to test-results/latest.md. It's meant to be run locally
# (`bin/rails test:report`) or from CI, where the resulting file gets
# uploaded as a build artifact (see .github/workflows/ci.yml).

require "open3"
require "json"
require "fileutils"
require "time"

namespace :test do
  desc "Run bin/rails test + bin/rubocop and write a summary to test-results/latest.md"
  task report: :environment do
    report_dir = Rails.root.join("test-results")
    FileUtils.mkdir_p(report_dir)
    report_path = report_dir.join("latest.md")

    puts "==> Running bin/rails test..."
    test_output, test_status = Open3.capture2e("bin/rails", "test")
    puts test_output

    puts "\n==> Running bin/rubocop..."
    rubocop_json, _rubocop_status = Open3.capture2("bin/rubocop", "--format", "json")

    test_summary = TestReport.parse_minitest(test_output)
    rubocop_summary = TestReport.parse_rubocop(rubocop_json)

    File.write(report_path, TestReport.render_markdown(
      generated_at: Time.now,
      test_summary: test_summary,
      test_exit_success: test_status.success?,
      rubocop_summary: rubocop_summary
    ))

    puts "\n==> Report written to #{report_path}"

    unless test_status.success? && rubocop_summary[:offense_count].zero?
      puts "==> test:report detected failures (see #{report_path})"
      exit(1)
    end
  end
end

# Small helper module that does the actual parsing/rendering, kept out of
# the rake task body so it's easy to read (and could be unit tested if
# desired).
module TestReport
  MINITEST_SUMMARY_REGEX = /(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips/
  MINITEST_FAILURE_REGEX = /^\s*\d+\)\s*(Failure|Error):\n(.+?)(?=\n\n|\z)/m

  def self.parse_minitest(output)
    match = MINITEST_SUMMARY_REGEX.match(output)

    unless match
      return { runs: 0, assertions: 0, failures: 0, errors: 0, skips: 0, details: [], raw_summary_found: false }
    end

    details = output.scan(MINITEST_FAILURE_REGEX).map { |kind, body| "#{kind}: #{body.strip}" }

    {
      runs: match[1].to_i,
      assertions: match[2].to_i,
      failures: match[3].to_i,
      errors: match[4].to_i,
      skips: match[5].to_i,
      details: details,
      raw_summary_found: true
    }
  end

  def self.parse_rubocop(json_output)
    parsed = JSON.parse(json_output)
    summary = parsed["summary"] || {}

    offenses = parsed["files"].to_a.flat_map do |file|
      file["offenses"].to_a.map do |offense|
        "#{file["path"]}:#{offense.dig("location", "line")} — #{offense["message"]}"
      end
    end

    {
      inspected_file_count: summary["inspected_file_count"].to_i,
      offense_count: summary["offense_count"].to_i,
      offenses: offenses
    }
  rescue JSON::ParserError
    { inspected_file_count: 0, offense_count: 0, offenses: [], parse_error: true }
  end

  def self.render_markdown(generated_at:, test_summary:, test_exit_success:, rubocop_summary:)
    lines = []
    lines << "# Test Results Report"
    lines << ""
    lines << "Generated: #{generated_at.utc.iso8601}"
    lines << ""
    lines << "## Test Suite (`bin/rails test`)"
    lines << ""

    if test_summary[:raw_summary_found]
      lines << "- Status: #{test_exit_success ? "PASS" : "FAIL"}"
      lines << "- Runs: #{test_summary[:runs]}"
      lines << "- Assertions: #{test_summary[:assertions]}"
      lines << "- Failures: #{test_summary[:failures]}"
      lines << "- Errors: #{test_summary[:errors]}"
      lines << "- Skips: #{test_summary[:skips]}"
    else
      lines << "- Status: UNKNOWN (could not parse Minitest summary line — see raw output in CI logs)"
    end

    lines << ""
    lines << "### Failures / Errors"
    lines << ""
    if test_summary[:details].present?
      test_summary[:details].each { |d| lines << "- #{d}" }
    else
      lines << "None"
    end

    lines << ""
    lines << "## RuboCop (`bin/rubocop`)"
    lines << ""
    lines << "- Status: #{rubocop_summary[:offense_count].zero? ? "PASS" : "FAIL"}"
    lines << "- Files inspected: #{rubocop_summary[:inspected_file_count]}"
    lines << "- Offenses: #{rubocop_summary[:offense_count]}"
    lines << ""
    lines << "### Offenses"
    lines << ""
    if rubocop_summary[:offenses].present?
      rubocop_summary[:offenses].each { |o| lines << "- #{o}" }
    else
      lines << "None"
    end

    lines << ""
    lines.join("\n")
  end
end
