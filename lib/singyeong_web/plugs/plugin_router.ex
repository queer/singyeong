defmodule SingyeongWeb.Plugs.PluginRouter do
  @moduledoc """
  A plug that routes requests to plugins.

  Since plugins dynamically define routes, we can't actually have them baked
  into the Phoenix router -- at least, not without some runtime bullshit with
  code loading that I honestly really don't wanna do. Instead, we can just
  forward all requests to this route and do some fuckery to properly parse out
  URL params and whatnot.
  """

  alias Singyeong.Plugin.RestRoute
  alias Singyeong.PluginManager
  alias Singyeong.Utils

  @behaviour Plug

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: path_info, method: conn_method} = conn, _opts) do
    path = "/#{Enum.join(path_info, "/")}"
    method =
      conn_method
      |> String.downcase
      |> String.to_atom

    :rest
    |> PluginManager.plugins_with_manifest
    |> Enum.filter(fn {_, manifest} ->
      Enum.any? manifest.rest_routes, fn %RestRoute{route: route, method: plugin_method} ->
        route_parses? =
          case Utils.parse_route(route, path) do
            {:ok, _} ->
              true

            :error ->
              false
          end

        plugin_method == method and route_parses?
      end
    end)
    |> Enum.reduce(conn, fn {plugin, manifest}, acc ->
      manifest.rest_routes
      |> Enum.map(fn route -> {route, Utils.parse_route(route.route, path)} end)
      |> Enum.filter(fn {_, parsed} -> parsed != :error end)
      |> Enum.reduce(acc, fn {route_manifest, {:ok, params}}, acc2 ->
        apply plugin, route_manifest.function, [acc2, params]
      end)
    end)
  end
end
