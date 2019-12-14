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

      is_list(a) and is_list(b) ->
        # See https://github.com/devonestes/fast-elixir/blob/master/code/general/concat_vs_cons.exs
        List.flatten [a | b]

      is_list(a) and not is_list(b) ->
        fast_list_concat a, [b]

      not is_list(a) and is_list(b) ->
        fast_list_concat [a], b
    end
  end

  # Check out https://stackoverflow.com/a/43881511
  def module_loaded?(module), do: function_exported?(module, :__info__, 1)
end
