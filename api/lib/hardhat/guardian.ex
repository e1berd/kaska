defmodule Hardhat.Guardian do
  use Guardian, otp_app: :hardhat

  alias Hardhat.Accounts
  alias Hardhat.Guardian.Token
  alias Hardhat.Repo

  def subject_for_token(%Accounts.User{id: id}, _claims), do: {:ok, to_string(id)}
  def subject_for_token(_, _), do: {:error, :invalid_resource}

  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_), do: {:error, :invalid_claims}

  def after_encode_and_sign(_resource, %{"typ" => "refresh"} = claims, token, _options) do
    attrs = %{
      jti: claims["jti"],
      aud: claims["aud"],
      typ: claims["typ"],
      iss: claims["iss"],
      sub: claims["sub"],
      exp: claims["exp"],
      jwt: token,
      claims: claims
    }

    case Repo.insert(Token.changeset(%Token{}, attrs)) do
      {:ok, _} -> {:ok, token}
      {:error, _} -> {:error, :token_storage_failure}
    end
  end

  def after_encode_and_sign(_resource, _claims, token, _options), do: {:ok, token}

  def on_verify(%{"typ" => "access"} = claims, _token, _options), do: {:ok, claims}

  def on_verify(%{"jti" => jti} = claims, _token, _options) do
    case Repo.get(Token, jti) do
      nil -> {:error, :token_not_found}
      _token -> {:ok, claims}
    end
  end

  def on_revoke(%{"jti" => jti} = claims, _token, _options) do
    case Repo.get(Token, jti) do
      nil ->
        {:ok, claims}

      token ->
        Repo.delete(token)
        |> case do
          {:ok, _} -> {:ok, claims}
          {:error, _} -> {:error, :token_revoke_failure}
        end
    end
  end
end
