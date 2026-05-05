import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/hardhat start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :hardhat, HardhatWeb.Endpoint, server: true
end

config :hardhat, HardhatWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# --- Cross-env overrides (apply in dev too, so docker-compose can drive everything) ---

if database_url = System.get_env("DATABASE_URL") do
  config :hardhat, Hardhat.Repo, url: database_url
end

# Bind to 0.0.0.0 when running inside docker so the host can reach us.
if System.get_env("BIND_ALL") in ["1", "true"] or System.get_env("DATABASE_URL") do
  config :hardhat, HardhatWeb.Endpoint, http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))]
end

# Allow the web SPA origin to open WebSocket connections.
web_base_url = System.get_env("WEB_BASE_URL")

if web_base_url do
  config :hardhat, HardhatWeb.Endpoint, check_origin: [web_base_url]
end

guardian_secret =
  System.get_env("GUARDIAN_SECRET_KEY") ||
    if config_env() == :prod do
      raise "environment variable GUARDIAN_SECRET_KEY is missing"
    else
      "dev_only_guardian_secret_key_replace_via_env_DO_NOT_USE_IN_PROD"
    end

config :hardhat, Hardhat.Guardian, secret_key: guardian_secret

# --- S3 / RustFS ---
config :hardhat, :s3,
  bucket: System.get_env("S3_BUCKET", "hardhat"),
  internal_endpoint: System.get_env("S3_INTERNAL_ENDPOINT", "http://rustfs:9000"),
  public_endpoint: System.get_env("S3_PUBLIC_ENDPOINT", "http://localhost:9000")

config :ex_aws,
  access_key_id: System.get_env("S3_ACCESS_KEY", "rustfsadmin"),
  secret_access_key: System.get_env("S3_SECRET_KEY", "rustfsadmin")

if internal = System.get_env("S3_INTERNAL_ENDPOINT") do
  uri = URI.parse(internal)

  config :ex_aws, :s3,
    scheme: "#{uri.scheme}://",
    host: uri.host,
    port: uri.port
end

if mail_host = System.get_env("MAIL_HOST") do
  config :hardhat, Hardhat.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: mail_host,
    port: String.to_integer(System.get_env("MAIL_PORT", "1025")),
    auth: :never,
    ssl: false,
    tls: :never,
    retries: 1,
    no_mx_lookups: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :hardhat, Hardhat.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :hardhat, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :hardhat, HardhatWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :hardhat, HardhatWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :hardhat, HardhatWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :hardhat, Hardhat.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
