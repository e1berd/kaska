defmodule KaskaWeb.ChannelCase do
  @moduledoc "Test case for channel tests, with the SQL sandbox and `Phoenix.ChannelTest`."

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import KaskaWeb.ChannelCase

      @endpoint KaskaWeb.Endpoint
    end
  end

  setup tags do
    Kaska.DataCase.setup_sandbox(tags)
    :ok
  end

  def user_socket(user) do
    Phoenix.ChannelTest.__socket__(
      KaskaWeb.UserSocket,
      nil,
      %{current_user: user},
      KaskaWeb.Endpoint
    )
  end
end
