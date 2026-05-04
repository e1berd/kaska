defmodule Hardhat.RankTest do
  use ExUnit.Case, async: true

  alias Hardhat.Rank

  describe "between/2" do
    test "open ends produce the initial rank" do
      assert Rank.between(nil, nil) == "U"
    end

    test "produces strictly ordered ranks for left-open insertions" do
      r1 = Rank.between(nil, "U")
      assert r1 < "U"
      assert r1 > ""
    end

    test "produces strictly ordered ranks for right-open insertions" do
      r1 = Rank.between("U", nil)
      assert r1 > "U"
    end

    test "midpoint between distant ranks is short" do
      r = Rank.between("A", "Z")
      assert "A" < r
      assert r < "Z"
      assert byte_size(r) == 1
    end

    test "midpoint between immediate neighbours extends" do
      r = Rank.between("U", "V")
      assert "U" < r
      assert r < "V"
    end

    test "raises when prev >= next" do
      assert_raise ArgumentError, fn -> Rank.between("V", "U") end
      assert_raise ArgumentError, fn -> Rank.between("U", "U") end
    end

    test "1000 sequential left insertions stay bounded and ordered" do
      Enum.reduce(1..1000, {nil, []}, fn _, {right, acc} ->
        r = Rank.between(nil, right)
        if right, do: assert(r < right)
        {r, [r | acc]}
      end)
    end

    test "1000 sequential right insertions stay bounded and ordered" do
      Enum.reduce(1..1000, {nil, []}, fn _, {left, acc} ->
        r = Rank.between(left, nil)
        if left, do: assert(r > left)
        {r, [r | acc]}
      end)
    end

    test "repeated midpoint insertions preserve total order" do
      ranks =
        Enum.reduce(1..50, ["A", "Z"], fn _, acc ->
          [a, b | _] = acc
          [a, Rank.between(a, b) | tl(acc)]
        end)

      assert ranks == Enum.sort(ranks)
      assert length(ranks) == length(Enum.uniq(ranks))
    end
  end
end
