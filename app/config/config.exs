import Config

config :kaska,
  ecto_repos: [Kaska.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :kaska, KaskaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: KaskaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kaska.PubSub,
  live_view: [signing_salt: "rgJW2Vkr"]

config :kaska, Kaska.Mailer, adapter: Swoosh.Adapters.Local

config :kaska, Kaska.Guardian,
  issuer: "kaska",
  ttl: {15, :minutes},
  allowed_algos: ["HS512"]

config :ex_aws,
  json_codec: Jason,
  region: "us-east-1",
  http_client: Kaska.S3.ReqClient

config :ex_aws, :s3,
  scheme: "http://",
  host: "rustfs",
  port: 9000

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
