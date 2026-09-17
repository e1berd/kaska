defmodule Kaska.Encrypted.Binary do
  @moduledoc "Ecto type for a binary field encrypted with `Kaska.Vault`."

  use Cloak.Ecto.Binary, vault: Kaska.Vault
end
