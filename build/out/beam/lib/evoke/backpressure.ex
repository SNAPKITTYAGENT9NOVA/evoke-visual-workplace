defmodule Evoke.Backpressure do
  @max_queue 100_000

  @moduledoc """
  Demand-driven Dylan frame producer in pure OTP — GenStage semantics,
  zero dependencies.

  The producer owns a FIFO queue of pending `{agent_id, op_code, payload}`
  jobs plus outstanding per-consumer demand. Frames are encoded and
  delivered as `{:dylan_frame, packet}` **only while demand is available**;
  with zero demand nothing flows, no matter how deep the queue is.

  `set_congestion/1` models a congested downstream (e.g. a saturated
  Metal client): while congested, emission pauses but demand and queued
  jobs are retained, so clearing congestion resumes losslessly.

  The queue is bounded (#{@max_queue} jobs); beyond that the newest jobs
  are dropped and counted (`dropped` in `stats/0`) instead of growing
  memory without bound. Consumer deaths are cleaned up via monitors so
  dead consumers never pin demand.

  This module exists so the mesh needs neither GenStage nor Broadway:
  demand accounting, queueing, congestion, and consumer-death cleanup are
  all implemented on top of `GenServer` + `:queue`, keeping `mix test`
  offline with no hex packages.
  """
  use GenServer

  alias Evoke.DylanProtocol

  defstruct queue: nil, pending: [], congested: false, emitted: 0, dropped: 0, monitors: %{}

  @type stats :: %{
          queued: non_neg_integer(),
          pending_demand: non_neg_integer(),
          emitted: non_neg_integer(),
          dropped: non_neg_integer(),
          congested: boolean()
        }

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Queues one pending Dylan frame job. Dropped (and counted) if the queue is full."
  @spec enqueue(binary(), 0..255, binary()) :: :ok
  def enqueue(agent_id, op_code, payload) do
    GenServer.cast(__MODULE__, {:enqueue, agent_id, op_code, payload})
  end

  @doc "Requests `n` frames for `consumer`; each is delivered as `{:dylan_frame, packet}`."
  @spec request_demand(pid(), pos_integer()) :: :ok
  def request_demand(consumer, n) when is_pid(consumer) and is_integer(n) and n > 0 do
    GenServer.cast(__MODULE__, {:demand, consumer, n})
  end

  @doc "Sets the congestion signal; while true, emission pauses (demand and queue retained)."
  @spec set_congestion(boolean()) :: :ok
  def set_congestion(flag) when is_boolean(flag) do
    GenServer.call(__MODULE__, {:set_congestion, flag})
  end

  @doc "Current producer state: queue depth, outstanding demand, counters, congestion."
  @spec stats() :: stats()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Drains the queue and zeroes counters. Intended for tests."
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_) do
    {:ok, %__MODULE__{queue: :queue.new()}}
  end

  @impl true
  def handle_cast({:enqueue, agent_id, op_code, payload}, state)
      when is_binary(agent_id) and byte_size(agent_id) == 16 and is_integer(op_code) and
             op_code >= 0 and op_code <= 255 and is_binary(payload) do
    if :queue.len(state.queue) < @max_queue do
      queue = :queue.in({agent_id, op_code, payload}, state.queue)
      {:noreply, dispatch(%{state | queue: queue})}
    else
      {:noreply, %{state | dropped: state.dropped + 1}}
    end
  end

  # Malformed jobs are dropped and counted, never allowed to crash the producer.
  def handle_cast({:enqueue, _agent_id, _op_code, _payload}, state) do
    {:noreply, %{state | dropped: state.dropped + 1}}
  end

  @impl true
  def handle_cast({:demand, consumer, n}, state) do
    state = %{state | monitors: ensure_monitored(state.monitors, consumer)}
    {:noreply, dispatch(%{state | pending: state.pending ++ [{consumer, n}]})}
  end

  @impl true
  def handle_call({:set_congestion, flag}, _from, state) do
    {:reply, :ok, dispatch(%{state | congested: flag})}
  end

  def handle_call(:stats, _from, state) do
    reply = %{
      queued: :queue.len(state.queue),
      pending_demand: Enum.reduce(state.pending, 0, fn {_pid, n}, acc -> acc + n end),
      emitted: state.emitted,
      dropped: state.dropped,
      congested: state.congested
    }

    {:reply, reply, state}
  end

  def handle_call(:reset, _from, state) do
    Enum.each(state.monitors, fn {_pid, ref} -> Process.demonitor(ref, [:flush]) end)
    {:reply, :ok, %__MODULE__{queue: :queue.new()}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = %{
      state
      | monitors: Map.delete(state.monitors, pid),
        pending: Enum.reject(state.pending, fn {p, _n} -> p == pid end)
    }

    {:noreply, state}
  end

  defp ensure_monitored(monitors, pid) do
    if Map.has_key?(monitors, pid) do
      monitors
    else
      Map.put(monitors, pid, Process.monitor(pid))
    end
  end

  # Emit only while there is outstanding demand and no congestion.
  # Tail-recursive: safe for deep queues.
  defp dispatch(%{congested: true} = state), do: state
  defp dispatch(%{pending: []} = state), do: state

  defp dispatch(state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        state

      {{:value, {agent_id, op_code, payload}}, queue} ->
        [{consumer, n} | pending] = state.pending
        packet = DylanProtocol.encode(agent_id, op_code, payload)
        send(consumer, {:dylan_frame, packet})
        pending = if n > 1, do: [{consumer, n - 1} | pending], else: pending

        dispatch(%{state | queue: queue, pending: pending, emitted: state.emitted + 1})
    end
  end
end
