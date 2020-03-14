defmodule Singyeong.PluginManager do
  @moduledoc """
  The plugin manager is responsible for loading and setting up plugins at
  runtime, as well as for providing an interface for interaction with plugins.
  """

  alias Singyeong.Env
  alias Singyeong.Plugin.{Capabilities, Manifest}
  alias Singyeong.Utils
  require Logger

  @plugins "./plugins"
  @ets_opts [:named_table, :public, :set, read_concurrency: true]

  def init(files \\ nil) do
    unless :ets.whereis(:plugins) == :undefined do
      shutdown()
    end
    :ets.new :plugins, @ets_opts
    if :ets.whereis(:loaded_so_cache) == :undefined do
      Logger.debug "[PLUGIN] Created new so cache"
      :ets.new :loaded_so_cache, @ets_opts
    end
    for capability <- Capabilities.capabilities() do
      :ets.new capability, @ets_opts
    end
    Logger.info "[PLUGIN] Loading plugins..."
    File.mkdir_p! @plugins
    plugin_mods =
      if files == nil do
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
      else
        files
        |> Enum.flat_map(fn zip -> load_plugin_from_zip(zip, false) end)
      end

    plugin_mods
    |> Enum.each(fn mod ->
      manifest = mod.manifest()
      Logger.debug "[PLUGIN] Loaded plugin #{mod} with manifest #{inspect manifest, pretty: true}"
      :ets.insert :plugins, {mod, manifest}
      for capability <- manifest.capabilities do
        if Capabilities.is_capability?(capability) do
          :ets.insert capability, {mod, manifest}
        else
          Logger.warn "[PLUGIN] Plugin #{manifest.name} attempted to register capability #{capability}, but it's not real!"
        end
      end
    end)
    Logger.debug "[PLUGIN] Loaded plugin modules: #{inspect plugin_mods, pretty: true}"
  end

  def shutdown do
    plugins_with_manifest()
    |> Enum.each(fn {mod, manifest} ->
      if manifest.native_modules != [] do
        :code.purge mod
      end
    end)
    :ets.delete :plugins
    for capability <- Capabilities.capabilities() do
      :ets.delete capability
    end
  end

  @spec plugins() :: [atom()] | []
  def plugins do
    :plugins
    |> :ets.tab2list
    |> Enum.map(fn {mod, _} -> mod end)
  end

  @spec plugins(atom()) :: [atom()] | []
  def plugins(capability) do
    if Capabilities.is_capability?(capability) do
      capability
      |> :ets.tab2list
      |> Enum.map(fn {mod, _} -> mod end)
    else
      # TODO: Throw?
      []
    end
  end

  @spec plugins_with_manifest() :: Keyword.t(Manifest.t())
  def plugins_with_manifest do
    :plugins
    |> :ets.tab2list
    |> Keyword.new
  end

  @spec plugins_with_manifest(atom()) :: Keyword.t(Manifest.t())
  def plugins_with_manifest(capability) do
    if Capabilities.is_capability?(capability) do
      capability
      |> :ets.tab2list
      |> Keyword.new
    else
      # TODO: Throw?
      []
    end
  end

  @spec plugins_for_event(atom(), binary()) :: [atom()]
  def plugins_for_event(capability, event) do
    # TODO: Convert this to be cleaner
    capability
    |> plugins_with_manifest
    |> Enum.filter(fn {_, manifest} ->
      event in manifest.events
    end)
    |> Enum.map(fn {plugin, _} -> plugin end)
    |> Enum.filter(fn plugin ->
      function_exported? plugin, :handle_event, 2
    end)
  end

  def plugins_for_auth do
    :auth
    |> plugins
    |> Enum.filter(fn plugin ->
      function_exported? plugin, :auth, 2
    end)
  end

  def plugin_auth(auth, ip) do
    case plugins_for_auth() do
      [] ->
        if Env.auth() == auth do
          :ok
        else
          :restricted
        end
      plugins when is_list(plugins) ->
        plugin_auth_results =
          plugins
          |> Enum.map(fn plugin -> plugin.auth(auth, ip) end)

        errors =
          plugin_auth_results
          |> Enum.filter(fn res -> {:error, _} = res end)
          |> Enum.map(fn {:error, msg} -> msg end)

        cond do
          length(errors) > 0 ->
            {:error, errors}

          Enum.any?(plugin_auth_results, fn elem -> elem == :restricted end) ->
            :restricted

          true ->
            :ok
        end
    end
  end

  @spec manifest(atom()) :: {:ok, Manifest.t()} | {:error, :no_plugin}
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

  def load_plugin_from_zip(path, allow_module_overrides \\ true) do
    zip_name =
      path
      |> String.split("/")
      |> Enum.reverse
      |> hd

    path = to_charlist path

    Logger.debug "[PLUGIN] Loading plugin from: #{zip_name}"
    {:ok, handle} = :zip.zip_open path, [:memory]
    {:ok, dir_list} = :zip.zip_list_dir handle

    File.mkdir_p! "#{System.tmp_dir!()}/natives"
    dir_list
    |> get_files
    |> Enum.map(&zip_file_name/1)
    |> Enum.filter(fn file ->
      file
      |> to_string
      |> String.starts_with?("natives/")
    end)
    |> Enum.each(fn file ->
      unless to_string(file) == "natives/" do
        case :ets.lookup(:loaded_so_cache, file) do
          [{file, true}] ->
            Logger.debug "[PLUGIN] Skipping native #{file}, load cached"
          _ ->
            Logger.debug "[PLUGIN] Attempting native extraction: #{file}"
            {:ok, {_, zip_data}} = :zip.zip_get file, handle
            native_path = "#{System.tmp_dir!()}/#{file}"
            File.write! native_path, zip_data
            Logger.debug "[PLUGIN] Extracted new native file to #{native_path}"
            :ets.insert :loaded_so_cache, {file, true}
        end
      end
    end)

    dir_list
    |> get_files
    |> Enum.filter(fn file ->
      file
      |> zip_file_name
      |> to_string
      |> String.ends_with?(".beam")
    end)
    |> Enum.map(fn file ->
      file_name = zip_file_name file
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
          not Utils.module_loaded? module_name
        end

      if can_load? do
        # We convert back to a charlist here because :code doesn't take binaries
        beam_file_name = to_charlist beam_file_name
        Logger.debug "[PLUGIN] Loaded BEAM file #{beam_file_name}, #{byte_size(zip_data)} bytes"
        :code.load_binary module_name, beam_file_name, zip_data
        Logger.debug "[PLUGIN] Loaded new module: #{module_name}"
      else
        Logger.warn "[PLUGIN] Not redefining already-existing module #{module_name}"
      end
      module_name
    end)
    # The previous step returns nil if it can't redefine a mod, so we have to
    # make sure that we filter that out
    |> Enum.filter(fn mod -> not is_nil(mod) end)
    # Scan for modules implementing Singyeong.Plugin
    |> Enum.map(fn mod -> {mod, mod.module_info()[:attributes][:behaviour]} end)
    |> Enum.filter(fn {_, behaviours} -> behaviours != nil and Singyeong.Plugin in behaviours end)
    |> Enum.map(fn {mod, _} -> mod end)
  end

  defp zip_file_name({:zip_file, file_name, _metadata, _, _, _}) do
    file_name
  end

  defp get_files(zip_list) do
    zip_list
    |> Enum.filter(fn tuple ->
      kind =
        tuple
        |> Tuple.to_list
        |> hd

      kind == :zip_file
    end)
  end
end
