defmodule Jiffy do
  @moduledoc """
  Jiffy adapter for using it as Phoenix JSON encoder.
  """

  # For Elixir and JavaScript compatilibity.
  @encode_opts [:strip_elixir_struct, :bigint_as_string, :use_nil]
  @decode_opts [:return_maps, :use_nil]

  @doc false
  @spec encode(any, opts :: List.t) :: {:ok, any()}
  def encode(value, opts \\ []) do
    {:ok, encode!(value, opts)}
  end

  @doc false
  @spec encode!(any, opts :: List.t) :: any()
  def encode!(value, opts \\ []) do
    :jiffy.encode(value, @encode_opts ++ opts)
  end

  @doc false
  @spec decode(String.t, opts :: List.t) :: {:ok, any()} | {:error, atom()}
  def decode(value, opts \\ []) do
    try do
      {:ok, :jiffy.decode(value, @decode_opts ++ opts)}
    catch
      error -> error
    end
  end

  @doc false
  @spec decode!(String.t, opts :: List.t) :: any() | no_return()
  def decode!(value, opts \\ []) do
    try do
      :jiffy.decode(value, @decode_opts ++ opts)
    catch
      _ -> raise ArgumentError
    end
  end

  @doc false
  @spec encode_to_iodata(any(), opts :: List.t) :: {:ok, charlist()}
  def encode_to_iodata(value, opts \\ []) do
    {:ok, encode_to_iodata!(value, opts)}
  end

  @doc false
  @spec encode_to_iodata!(any(), opts :: List.t) :: charlist()
  def encode_to_iodata!(value, opts \\ []) do
    encode!(value, opts)
  end
end
