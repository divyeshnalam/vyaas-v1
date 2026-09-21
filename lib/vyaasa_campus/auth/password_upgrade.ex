defmodule VyaasaCampus.Auth.PasswordUpgrade do
  @moduledoc """
  Transparently upgrades a stored bcrypt hash to the currently-configured work
  factor on successful login (we have the plaintext at that moment).

  Lowering `:bcrypt_elixir, :log_rounds` only affects newly-created hashes —
  existing accounts keep the cost embedded in their stored hash, so they stay
  slow until re-hashed. Bcrypt is one-way, so the only way to re-hash without a
  password reset is to do it during a verified login. Call `maybe_rehash/2`
  after a successful `verify_pass` and persist the result if it changed.
  """

  @doc """
  Compare the stored hash's cost to the configured target.

  Returns `{:rehash, new_hash}` when they differ (caller should persist it), or
  `:keep` when they match or the hash can't be parsed. Only call this after the
  password has already verified — `plaintext` must be the correct password.
  """
  def maybe_rehash(stored_hash, plaintext) when is_binary(stored_hash) and is_binary(plaintext) do
    target = Application.get_env(:bcrypt_elixir, :log_rounds, 12)

    case stored_cost(stored_hash) do
      ^target -> :keep
      nil -> :keep
      _other -> {:rehash, Bcrypt.hash_pwd_salt(plaintext)}
    end
  end

  def maybe_rehash(_, _), do: :keep

  # bcrypt hashes look like "$2b$12$<salt+digest>" — the 3rd "$"-segment is cost.
  defp stored_cost("$2" <> _ = hash) do
    case String.split(hash, "$") do
      [_, _algo, cost | _] ->
        case Integer.parse(cost) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp stored_cost(_), do: nil
end
