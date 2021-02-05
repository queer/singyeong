defmodule Singyeong.Utils do
  @moduledoc """
  Some utility functions that don't really belong in any one place.
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

  def ip_to_string(ip) do
    case ip do
      {a, b, c, d} ->
        "#{a}.#{b}.#{c}.#{d}"
      {a, b, c, d, e, f, g, h} ->
        "#{hex a}:#{hex b}:#{hex c}:#{hex d}:#{hex e}:#{hex f}:#{hex g}:#{hex h}"
    end
  end

  defp hex(v) do
    v
    |> Integer.to_string(16)
    |> String.pad_leading(4, "0")
    |> String.downcase
  end

  @spec parse_route(binary(), binary()) :: {:ok, map()} | :error
  def parse_route(template, actual) do
    template_parts = route_to_parts template
    actual_parts = route_to_parts actual

    zipped = Enum.zip template_parts, actual_parts
    length_same? = length(template_parts) == length(actual_parts)
    if length_same? and route_matches_template?(zipped) do
      params =
        zipped
        |> Enum.reduce(%{}, fn {template_part, actual_part}, acc ->
          if String.starts_with?(template_part, ":") do
            ":" <> param = template_part
            Map.put acc, param, actual_part
          else
            acc
          end
        end)

      {:ok, params}
    else
      :error
    end
  end

  defp route_to_parts(route) do
    route
    |> String.split(~r/\/+/)
    |> Enum.filter(fn part -> part != "" end)
  end

  defp route_matches_template?(zipped_list) do
    zipped_list
    |> Enum.all?(fn {template_part, actual_part} ->
      template_part == actual_part or String.starts_with?(template_part, ":")
    end)
  end

  def stringify_keys(map, recurse? \\ false)

  def stringify_keys(map, recurse?) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      if is_binary(k) do
        {k, stringify_keys(v)}
      else
        if recurse? do
          {Atom.to_string(k), stringify_keys(v)}
        else
          {Atom.to_string(k), v}
        end
      end
    end)
    |> Enum.into(%{})
  end

  def stringify_keys(not_map, _), do: not_map

  def destructify(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      cond do
        is_struct(v) ->
          {k, destructify(Map.from_struct(v))}

        is_map(v) ->
          {k, destructify(v)}

        is_list(v) ->
          {k, Enum.map(v, &destructify/1)}

        true ->
          {k, v}
      end
    end)
    |> Enum.into(%{})
  end

  def destructify(not_map), do: not_map

  def now, do: :os.system_time :millisecond

  def random_string(length) do
    length
    |> :crypto.strong_rand_bytes
    |> Base.url_encode64(padding: false)
  end
end
