source "https://rubygems.org"

ruby ">= 3.2"

gem "rails", "~> 8.1"
gem "propshaft"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "playwright-ruby-client"
gem "geocoder"
gem "chartkick"
gem "groupdate"
gem "caxlsx"
gem "caxlsx_rails"
gem "csv"
gem "ostruct" # used by SettingsController#test_email; moving out of Ruby's default gems in 4.0
gem "dnssd", require: false
gem "mail"
gem "faraday"
gem "faraday-multipart"
gem "amazing_print"
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
# bin/kamal and config/deploy.yml already assume this — without the gem,
# bin/kamal fails immediately with "could not find gem kamal".
gem "kamal", require: false

group :development, :test do
  gem "debug"

  # bin/bundler-audit, bin/brakeman, and bin/rubocop already exist and are
  # wired into .github/workflows/ci.yml's scan_ruby/lint jobs, but none of
  # these three gems were ever added — every CI run fails immediately on them.
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :test do
  # Minitest 6 dropped Mock/Object#stub from core — this is the same code,
  # published separately, so stubbing Faraday/network calls in tests works.
  gem "minitest-mock"
end

group :development do
  gem "web-console"
end
