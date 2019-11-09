defmodule Singyeong.PluginManager do
  @moduledoc """
  The plugin manager is responsible for loading and setting up plugins at
  runtime, as well as for providing an interface for interaction with plugins.
  """

  alias Singyeong.Utils
  require Logger

  @plugins "./plugins"

  def init do
    _table = :ets.new :plugins, [:named_table, :set, read_concurrency: true]
    Logger.info "[PLUGIN] Loading plugins..."
    File.mkdir_p! @plugins
    plugin_mods =
      @plugins
      |> File.ls!
      |> Enum.filter(fn file ->
        # Only attempt to load ZIPs
        file
        |> String.downcase
        |> String.ends_with?(".zip")
      end)
      |> Enum.map(fn file -> "#{@plugins}/#{file}" end)
      |> Enum.flat_map(fn zip -> load_plugin_from_zip(zip, false) end)
    plugin_mods
    |> Enum.each(fn mod ->
      Logger.debug "[PLUGIN] Loaded plugin #{mod} with manifest #{inspect mod.manifest(), pretty: true}"
      :ets.insert :plugins, {mod, mod.manifest()}
    end)
    Logger.debug "[PLUGIN] Loaded plugin modules: #{inspect plugin_mods, pretty: true}"
  end

  def plugins do
    :plugins
    |> :ets.tab2list
    |> Enum.map(fn {mod, _} -> mod end)
  end

  @spec manifest(atom()) :: {:ok, Singyeong.Plugin.Manifest.t()} | {:error, :no_plugin}
  def manifest(plugin) when is_atom(plugin) do
    case :ets.lookup(:plugins, plugin) do
      [] ->
        {:error, :no_plugin}
      [{^plugin, manifest}] ->
        {:ok, manifest}
      _ ->
        {:error, :no_plugin}
    end
  end

  def load_plugins do
    plugins()
    |> Enum.flat_map(fn plugin ->
      load_result = plugin.load()
      case load_result do
        {:ok, children} when is_list(children) ->
          children
        {:ok, nil} ->
          []
        {:error, reason} ->
          Logger.error "[PLUGIN] Failed loading plugin #{plugin}: #{reason}"
          []
      end
    end)
  end

  defp load_plugin_from_zip(path, allow_module_overrides \\ true) do
    zip_name =
      path
      |> String.split("/")
      |> Enum.reverse
      |> hd
    path = to_charlist path

    Logger.debug "[PLUGIN] Loading plugin from: #{zip_name}"
    {:ok, handle} = :zip.zip_open path, [:memory]
    {:ok, dir_list} = :zip.zip_list_dir handle

    dir_list
    |> Enum.filter(fn tuple ->
      kind =
        tuple
        |> Tuple.to_list
        |> hd
      kind == :zip_file
    end)
    |> Enum.filter(fn file ->
      {:zip_file, file_name, _metadata, _, _, _} = file
      file_name
      |> to_string
      |> String.ends_with?(".beam")
    end)
    |> Enum.map(fn file ->
      {:zip_file, file_name, _metadata, _, _, _} = file
      {:ok, {zip_file_name, zip_data}} = :zip.zip_get file_name, handle

      beam_file_name =
        zip_file_name
        |> to_string
        |> String.split("/")
        |> Enum.reverse
        |> hd
      module_name =
        beam_file_name
        |> String.replace_trailing(".beam", "")
        |> String.to_atom

      can_load? =
        if allow_module_overrides do
          true
        else
          not Utils.module_compiled? module_name
        end

      if can_load? do
        # We convert back to a charlist here because :code doesn't take binaries
        beam_file_name = to_charlist beam_file_name
        Logger.debug "[PLUGIN] Loaded BEAM file #{beam_file_name}, #{byte_size(zip_data)} bytes"
        :code.load_binary module_name, beam_file_name, zip_data
        Logger.debug "[PLUGIN] Loaded new module: #{module_name}"
        module_name
      else
        Logger.warn "[PLUGIN] Not redefining already-existing module #{module_name}"
        nil
      end
    end)
    # The previous step returns nil if it can't redefine a mod, so we have to
    # make sure that we filter that out
    |> Enum.filter(fn mod -> not is_nil(mod) end)
    # Scan for modules implementing Singyeong.Plugin
    |> Enum.map(fn mod -> {mod, mod.module_info()[:attributes][:behaviour]} end)
    |> Enum.filter(fn {_, behaviours} -> behaviours != nil and Singyeong.Plugin in behaviours end)
    |> Enum.map(fn {mod, _} -> mod end)
  end
end
