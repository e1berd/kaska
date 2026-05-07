import Config

config :hardhat,
  ecto_repos: [Hardhat.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :hardhat, HardhatWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: HardhatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hardhat.PubSub,
  live_view: [signing_salt: "rgJW2Vkr"]

config :hardhat, Hardhat.Mailer, adapter: Swoosh.Adapters.Local

config :hardhat, Hardhat.Guardian,
  issuer: "hardhat",
  ttl: {15, :minutes},
  allowed_algos: ["HS512"]

config :ex_aws,
  json_codec: Jason,
  region: "us-east-1",
  http_client: Hardhat.S3.ReqClient

config :ex_aws, :s3,
  scheme: "http://",
  host: "rustfs",
  port: 9000

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
