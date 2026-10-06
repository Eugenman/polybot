import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :polybot, Polybot.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "polybot_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :polybot, PolybotWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Na28Hu691XVQ8gRagurebPhRrfabPL9a6MZXG+eQINZbg7dpOEUk9DZJQLTED1DJ",
  server: false

# No background scanning in tests; HTTP calls go to Req.Test stubs.
config :polybot, start_scheduler: false

config :polybot, Polybot.Polymarket.Gamma,
  req_options: [plug: {Req.Test, Polybot.Polymarket.Gamma}, retry: false]

config :polybot, Polybot.AI.Analyst,
  req_options: [plug: {Req.Test, Polybot.AI.Analyst}, retry: false],
  api_key: "test-api-key"

config :polybot, Polybot.Scheduler, request_delay_ms: 0

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
