defmodule Singyeong.Gateway.Encoding do
  alias Phoenix.Socket
  alias Singyeong.Gateway.Payload
  alias Singyeong.Utils

  @valid_encodings [
    "json",
    "msgpack",
    "etf",
  ]

  @spec validate_encoding(binary()) :: boolean()
  def validate_encoding(encoding) when is_binary(encoding), do: encoding in @valid_encodings

  @spec encode(Socket.t(), {any(), any()} | Payload.t()) :: {:binary, any()} | {:text, binary()}
  def encode(socket, data) do
    encoding = socket.assigns[:encoding] || "json"
    case data do
      {_, payload} ->
        encode_real encoding, payload

      _ ->
        encode_real encoding, data
    end
  end

  @spec encode_real(binary(), any()) :: {:binary, binary()} | {:text, binary()}
  def encode_real(encoding, payload) do
    payload = to_outgoing payload
    case encoding do
      "json" ->
        {:ok, term} = Jason.encode payload
        {:text, term}

      "msgpack" ->
        {:ok, term} = Msgpax.pack payload
        # msgpax returns iodata, so we convert it to binary for consistency
        {:binary, IO.iodata_to_binary(term)}

      "etf" ->
        term =
          payload
          |> Utils.destructify
          |> :erlang.term_to_binary

        {:binary, term}
    end
  end

  @spec decode_payload(:text | :binary, binary(), String.t(), boolean()) :: {:ok, Payload.t()} | {:error, term()}
  def decode_payload(opcode, payload, encoding, restricted) do
    case {opcode, encoding} do
      {:text, "json"} ->
        # JSON has to be error-checked for error conversion properly
        {status, data} = Jason.decode payload
        case status do
          :ok ->
            {:ok, Payload.from_map(data)}

          :error ->
            {:error, Exception.message(data)}
        end

      {:binary, "msgpack"} ->
        # MessagePack has to be unpacked and error-checked
        {status, data} = Msgpax.unpack payload
        case status do
          :ok ->
            {:ok, Payload.from_map(data)}

          :error ->
            # We convert the exception into smth more useful
            {:error, Exception.message(data)}
        end

      {:binary, "etf"} ->
        decode_etf payload, restricted

      _ ->
        {:error, "invalid opcode/encoding combo: {#{opcode}, #{encoding}}"}
    end
  rescue
    _ ->
      {:error, "Couldn't decode payload"}
  end

  defp decode_etf(payload, restricted) do
    case restricted do
      true ->
        # If the client is restricted, but is sending us ETF, make it go
        # away
        {:error, "restricted clients may not use ETF"}

      false ->
        # If the client is NOT restricted and sends ETF, decode it.
        # In this particular case, we trust that the client isn't stupid
        # about the ETF it's sending
        term =
          payload
          |> :erlang.binary_to_term
          |> Utils.stringify_keys
          |> Payload.from_map

        {:ok, term}

      nil ->
        # If we don't yet know if the client will be restricted, decode
        # it in safe mode
        term =
          payload
          |> :erlang.binary_to_term([:safe])
          |> Utils.stringify_keys
          |> Payload.from_map

        {:ok, term}
    end
  end

  defp to_outgoing(%{__struct__: _} = payload) do
    Map.from_struct payload
  end

  defp to_outgoing(payload) do
    payload
  end
end
