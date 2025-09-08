ExUnit.start(max_cases: System.schedulers_online() * 2)

# Reduce test log noise; only warnings and errors will be emitted during tests
require Logger
Logger.configure(level: :warning)
