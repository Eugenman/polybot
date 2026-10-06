import Config

# Configure your database
config :polybot, Polybot.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "polybot_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :polybot, PolybotWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}],
  server: true,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "9+vrBtYg275n/SHc7iQfsdUJQiqqOoTHCffGAuaa2W57kU7IiekjC7yB18PZDxzt",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:polybot, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:polybot, ~w(--watch)]}
  ]

config :polybot, PolybotWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*\.po$",
      ~r"lib/polybot_web/router\.ex$",
      ~r"lib/polybot_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

config :polybot, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
