defmodule Singyeong.Utils do
  @moduledoc """
  Some utility functions that don't really belong in any one place
  """

  @spec fast_list_concat(list(), list()) :: list()
  def fast_list_concat(a, b) do
    # See https://github.com/devonestes/fast-elixir/blob/master/code/general/concat_vs_cons.exs
    List.flatten [a | b]
  end

  # Check out https://stackoverflow.com/a/43881511
  def module_compiled?(module), do: function_exported?(module, :__info__, 1)
end
