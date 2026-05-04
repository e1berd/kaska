defmodule Hardhat.Rank do
  @moduledoc """
  Fractional indexing over base-62 alphabet `[0-9A-Za-z]`.

  Ranks are short strings compared lexicographically. Inserting between two
  neighbours `a < b` is `between(a, b)`, producing `c` with `a < c < b` —
  no neighbour rewrites required.

  `nil` on either side denotes an open boundary (-inf / +inf).

  Algorithm: Figma-style midpoint with shared prefix detection. Adapted to
  base-62; the alphabet is monotonic in ASCII (`'0'` < `'9'` < `'A'` < `'Z'`
  < `'a'` < `'z'`), so byte-wise comparison is consistent with semantic order.
  """

  @alphabet ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @base length(@alphabet)
  @alphabet_index for {ch, i} <- Enum.with_index(@alphabet), into: %{}, do: {ch, i}

  @doc "Default rank for the very first element of an empty list."
  def initial, do: "U"

  @doc """
  Returns a rank strictly between `prev` and `next` (lexicographically).
  Pass `nil` for either side to denote an open boundary.

  Raises if `prev >= next`.
  """
  def between(prev, next)

  def between(nil, nil), do: initial()
  def between(nil, next) when is_binary(next), do: midpoint("", next)
  def between(prev, nil) when is_binary(prev), do: midpoint(prev, nil)

  def between(prev, next) when is_binary(prev) and is_binary(next) do
    if prev >= next do
      raise ArgumentError,
            "rank prev (#{inspect(prev)}) must be < next (#{inspect(next)})"
    end

    midpoint(prev, next)
  end

  # `a` is a string; "" means -inf.
  # `b` is a string or nil; nil means +inf.
  # Invariant: a < b (treating nil as +inf, "" as -inf).
  defp midpoint(a, b) do
    n = common_prefix_len(a, b, 0)

    if n > 0 do
      head =
        if is_binary(b) do
          binary_part(b, 0, n)
        else
          binary_part(a, 0, n)
        end

      head <>
        midpoint(
          slice_after(a, n),
          if(is_binary(b), do: slice_after(b, n), else: nil)
        )
    else
      digit_a = if a == "", do: 0, else: index_of(:binary.at(a, 0))
      digit_b = if is_binary(b), do: index_of(:binary.at(b, 0)), else: @base

      cond do
        digit_b - digit_a > 1 ->
          mid = div(digit_a + digit_b, 2)
          <<Enum.at(@alphabet, mid)>>

        is_binary(b) and byte_size(b) > 1 ->
          # No room at this digit — borrow b's first char and recurse into its
          # suffix. This avoids returning a rank whose suffix is the alphabet
          # minimum, preserving the invariant that left/right extensions can
          # always continue.
          binary_part(b, 0, 1) <> midpoint("", slice_after(b, 1))

        true ->
          {ch, rest_a} =
            if a == "" do
              {<<Enum.at(@alphabet, digit_a)>>, ""}
            else
              {binary_part(a, 0, 1), slice_after(a, 1)}
            end

          ch <> midpoint(rest_a, nil)
      end
    end
  end

  defp common_prefix_len(a, b, n) do
    has_a = byte_size(a) > n
    has_b = is_binary(b) and byte_size(b) > n

    cond do
      not has_a or not has_b -> n
      :binary.at(a, n) == :binary.at(b, n) -> common_prefix_len(a, b, n + 1)
      true -> n
    end
  end

  defp slice_after(s, n) when is_binary(s),
    do: binary_part(s, n, byte_size(s) - n)

  defp index_of(byte), do: Map.fetch!(@alphabet_index, byte)
end
