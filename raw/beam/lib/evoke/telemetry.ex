defmodule Evoke.Telemetry do
  @moduledoc """
  Lock-free mesh counters backed by `:counters` (OTP 21.2+).

  Tracked counters:

    * `:frames_encoded` — Dylan frames encoded by agent nodes
    * `:frames_dispatched` — frames fanned out to transports
    * `:crc_failures` — frames rejected by CRC verification
    * `:ws_clients` — currently connected WebSocket transports

  `snapshot/0` returns current values as a map; `reset/0` zeroes them
  (used by tests). The `:counters` reference is published via
  `:persistent_term` at init so `inc/1` is a single lock-free add with
  no GenServer round-trip on the hot path.
  """
  use GenServer

  @indices %{frames_encoded: 1, frames_dispatched: 2, crc_failures: 3, ws_clients: 4}
  @size map_size(@indices)

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec inc(:frames_encoded | :frames_dispatched | :crc_failures | :ws_clients) :: :ok
  def inc(counter) do
    :counters.add(ref(), Map.fetch!(@indices, counter), 1)
    :ok
  end

  @spec dec(:frames_encoded | :frames_dispatched | :crc_failures | :ws_clients) :: :ok
  def dec(counter) do
    :counters.add(ref(), Map.fetch!(@indices, counter), -1)
    :ok
  end

  @spec snapshot() :: %{
          frames_encoded: integer(),
          frames_dispatched: integer(),
          crc_failures: integer(),
          ws_clients: integer()
        }
  def snapshot do
    r = ref()
    Map.new(@indices, fn {name, idx} -> {name, :counters.get(r, idx)} end)
  end

  @spec reset() :: :ok
  def reset do
    r = ref()
    Enum.each(@indices, fn {_name, idx} -> :counters.put(r, idx, 0) end)
    :ok
  end

  @impl true
  def init(_) do
    ref = :counters.new(@size, [:write_concurrency])
    :persistent_term.put({__MODULE__, :ref}, ref)
    {:ok, %{ref: ref}}
  end

  defp ref, do: :persistent_term.get({__MODULE__, :ref})
end
