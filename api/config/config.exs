# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :hardhat,
  ecto_repos: [Hardhat.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :hardhat, HardhatWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: HardhatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hardhat.PubSub,
  live_view: [signing_salt: "rgJW2Vkr"]

# Mailer: Swoosh.Adapters.Local stores mail in memory and exposes /dev/mailbox.
# In dev/prod we override to SMTP (mailpit / real provider) in runtime.exs.
config :hardhat, Hardhat.Mailer, adapter: Swoosh.Adapters.Local

# Guardian (JWT-based auth, surfaced over Phoenix Channels)
config :hardhat, Hardhat.Guardian,
  issuer: "hardhat",
  ttl: {15, :minutes},
  allowed_algos: ["HS512"]

# Persist refresh tokens so they can be revoked. Access tokens stay stateless.
config :guardian, Guardian.DB,
  repo: Hardhat.Repo,
  schema_name: "guardian_tokens",
  token_types: ["refresh"],
  sweep_interval: 60

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
