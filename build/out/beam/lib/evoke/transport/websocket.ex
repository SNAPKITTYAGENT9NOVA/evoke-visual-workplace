defmodule Evoke.Transport.WebSocket do
  @moduledoc """
  Minimal RFC 6455 WebSocket server over `:gen_tcp`. Zero dependencies.

  Each accepted connection performs the HTTP upgrade handshake, then
  registers itself in `Evoke.Registry` under the `"dylan_transport"` topic,
  so `Evoke.AgentNode` fan-out reaches browsers / Metal clients verbatim.
  Inbound `{:dylan_frame, packet}` messages are sent as single unmasked
  binary frames (opcode `0x2`). Client ping frames are answered with pong,
  close frames are acknowledged, and anything else from the client is
  dropped — the mesh speaks one thing: Dylan binary frames.

  ## Deliberate tradeoffs (Woz-style)

    * No HTTP routing, TLS, compression, or fragmented-message reassembly.
    * One Erlang process per connection plus one acceptor; backpressure is
      the sender's job (`Evoke.Backpressure`), not the socket's.
    * Connections run with `active: :once` and a parse buffer, so control
      frames and outbound Dylan frames interleave without a blocked
      receiver.

  ## Drop-in upgrade path

  Replace `start_link/1` with a Cowboy (or Bandit) listener and keep the
  contract: register each connection pid under
  `{Evoke.Registry, "dylan_transport"}` and translate
  `{:dylan_frame, packet}` into a binary WebSocket frame. No other module
  needs to change.
  """
  use GenServer

  require Logger

  alias Evoke.Telemetry

  @registry Application.compile_env(:evoke, :registry, Evoke.Registry)
  @topic Application.compile_env(:evoke, :transport_topic, "dylan_transport")
  @ws_guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @max_headers 16_384

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    port = Keyword.fetch!(opts, :port)
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  def init(port) do
    {:ok, lsock} =
      :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true, backlog: 128])

    {:ok, _acceptor} = Task.start_link(fn -> accept_loop(lsock) end)
    Logger.info("dylan websocket transport listening on port #{port}")
    {:ok, %{listen: lsock, port: port}}
  end

  @impl true
  def terminate(_reason, %{listen: lsock}) do
    :gen_tcp.close(lsock)
    :ok
  end

  # -- acceptor ----------------------------------------------------------

  defp accept_loop(lsock) do
    case :gen_tcp.accept(lsock) do
      {:ok, sock} ->
        # Spawn-then-transfer avoids the race where the handler reads
        # before owning the socket: it blocks on :go until control moves.
        {:ok, pid} =
          Task.start_link(fn ->
            receive do
              :go -> serve(sock)
            end
          end)

        :ok = :gen_tcp.controlling_process(sock, pid)
        send(pid, :go)
        accept_loop(lsock)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.warning("dylan ws accept error: #{inspect(reason)}")
        accept_loop(lsock)
    end
  end

  # -- per-connection handler --------------------------------------------

  defp serve(sock) do
    :ok = :inet.setopts(sock, keepalive: true)

    case handshake(sock) do
      :ok ->
        {:ok, _} = Registry.register(@registry, @topic, %{})
        Telemetry.inc(:ws_clients)

        try do
          connection_loop(sock, <<>>)
        after
          Telemetry.dec(:ws_clients)
        end

      {:error, reason} ->
        Logger.debug("dylan ws handshake failed: #{inspect(reason)}")
        :gen_tcp.close(sock)
    end
  end

  defp connection_loop(sock, buffer) do
    :ok = :inet.setopts(sock, active: :once)

    receive do
      {:tcp, ^sock, data} ->
        case handle_client_data(sock, buffer <> data) do
          {:ok, rest} -> connection_loop(sock, rest)
          :closed -> :ok
        end

      {:tcp_closed, ^sock} ->
        :ok

      {:tcp_error, ^sock, reason} ->
        Logger.debug("dylan ws tcp error: #{inspect(reason)}")
        :ok

      {:dylan_frame, packet} ->
        :ok = :gen_tcp.send(sock, encode_frame(:binary, packet))
        connection_loop(sock, buffer)
    end
  end

  # -- HTTP upgrade handshake --------------------------------------------

  defp handshake(sock) do
    with {:ok, request} <- read_http_request(sock, <<>>),
         {:ok, key} <- websocket_key(request) do
      accept = :crypto.hash(:sha, key <> @ws_guid) |> Base.encode64()

      response =
        "HTTP/1.1 101 Switching Protocols\r\n" <>
          "Upgrade: websocket\r\n" <>
          "Connection: Upgrade\r\n" <>
          "Sec-WebSocket-Accept: #{accept}\r\n" <>
          "\r\n"

      :gen_tcp.send(sock, response)
    end
  end

  defp read_http_request(_sock, acc) when byte_size(acc) > @max_headers do
    {:error, :headers_too_large}
  end

  defp read_http_request(sock, acc) do
    case :gen_tcp.recv(sock, 0, 5_000) do
      {:ok, data} ->
        request = acc <> data

        if :binary.match(request, "\r\n\r\n") != :nomatch do
          {:ok, request}
        else
          read_http_request(sock, request)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp websocket_key(request) do
    key =
      request
      |> String.split("\r\n")
      |> Enum.find_value(fn
        "Sec-WebSocket-Key:" <> rest -> String.trim(rest)
        "sec-websocket-key:" <> rest -> String.trim(rest)
        _ -> nil
      end)

    if is_binary(key) and key != "", do: {:ok, key}, else: {:error, :missing_websocket_key}
  end

  # -- inbound client frame parsing ---------------------------------------

  defp handle_client_data(_sock, <<>>), do: {:ok, <<>>}

  defp handle_client_data(sock, buffer) do
    case parse_frame(buffer) do
      :incomplete ->
        {:ok, buffer}

      {:error, reason} ->
        Logger.debug("dylan ws frame error: #{inspect(reason)}")
        :gen_tcp.close(sock)
        :closed

      {:ok, %{opcode: 0x8}, _rest} ->
        :ok = :gen_tcp.send(sock, encode_frame(:close, <<>>))
        :gen_tcp.close(sock)
        :closed

      {:ok, %{opcode: 0x9, payload: payload}, rest} ->
        :ok = :gen_tcp.send(sock, encode_frame(:pong, payload))
        handle_client_data(sock, rest)

      {:ok, _frame, rest} ->
        # Text, binary, continuation, or pong from the client carry no
        # Dylan semantics; drop them and keep parsing pipelined frames.
        handle_client_data(sock, rest)
    end
  end

  # Client frames MUST be masked (RFC 6455 §5.1).
  defp parse_frame(<<_fin::1, _rsv::3, opcode::4, 1::1, 126::7, len::16-big, rest::binary>>) do
    parse_masked(opcode, len, rest)
  end

  defp parse_frame(<<_fin::1, _rsv::3, opcode::4, 1::1, 127::7, len::64-big, rest::binary>>) do
    parse_masked(opcode, len, rest)
  end

  defp parse_frame(<<_fin::1, _rsv::3, opcode::4, 1::1, len::7, rest::binary>>) when len < 126 do
    parse_masked(opcode, len, rest)
  end

  defp parse_frame(<<_fin::1, _rsv::3, _opcode::4, 0::1, _::7, _::binary>>) do
    {:error, :unmasked_client_frame}
  end

  defp parse_frame(_), do: :incomplete

  defp parse_masked(opcode, len, <<mask::binary-4, rest::binary>>) do
    if byte_size(rest) >= len do
      <<payload::binary-size(len), remaining::binary>> = rest
      {:ok, %{opcode: opcode, payload: unmask(mask, payload)}, remaining}
    else
      :incomplete
    end
  end

  defp parse_masked(_opcode, _len, _rest), do: :incomplete

  defp unmask(mask, payload) do
    key_stream = Stream.cycle(:binary.bin_to_list(mask))

    payload
    |> :binary.bin_to_list()
    |> Enum.zip(key_stream)
    |> Enum.map(fn {byte, key} -> Bitwise.bxor(byte, key) end)
    |> :binary.list_to_bin()
  end

  # -- outbound server frame encoding -------------------------------------

  # Server-to-client frames are never masked (RFC 6455 §5.1).
  defp encode_frame(:binary, payload), do: server_frame(0x2, payload)
  defp encode_frame(:pong, payload), do: server_frame(0xA, payload)
  defp encode_frame(:close, payload), do: server_frame(0x8, payload)

  defp server_frame(opcode, payload) when is_binary(payload) do
    len = byte_size(payload)

    header =
      cond do
        len < 126 -> <<1::1, 0::3, opcode::4, 0::1, len::7>>
        len < 65_536 -> <<1::1, 0::3, opcode::4, 0::1, 126::7, len::16-big>>
        true -> <<1::1, 0::3, opcode::4, 0::1, 127::7, len::64-big>>
      end

    <<header::binary, payload::binary>>
  end
end
