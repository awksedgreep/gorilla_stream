ExUnit.start(max_cases: System.schedulers_online() * 2)

# Configure test logging; default to :warning, allow override via LOG_LEVEL env var
require Logger

case System.get_env("LOG_LEVEL") do
  nil ->
    Logger.configure(level: :warning)

  level_str ->
    level =
      case String.downcase(level_str) do
        "debug" -> :debug
        "info" -> :info
        "warn" -> :warning
        "warning" -> :warning
        "error" -> :error
        _ -> :warning
      end

    Logger.configure(level: level)
end
