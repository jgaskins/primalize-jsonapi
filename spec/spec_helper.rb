require "bundler/setup"

GC.disable

start = Time.now
at_exit { puts "Specs ran in #{(Time.now - start) * 1000}ms" }
require "primalize/jsonapi"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
