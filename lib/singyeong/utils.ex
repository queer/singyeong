defmodule Singyeong.Utils do
  @moduledoc """
  Some utility functions that don't really belong in any one place
  """

  @spec fast_list_concat(list(), list()) :: list()
  def fast_list_concat(a, b) do
    # See #72 for why this check is needed
    cond do
      a == nil ->
        b

      b == nil ->
        a

      true ->
        # See https://github.com/devonestes/fast-elixir/blob/master/code/general/concat_vs_cons.exs
        List.flatten [a | b]
    end
  end
end
