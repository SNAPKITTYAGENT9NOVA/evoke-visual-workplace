defmodule Evoke.AgentNode do
  @moduledoc """
  A single mesh agent: a minimal GenServer holding only its 16-byte Dylan
  agent id and an emitted-frame counter.

  UI actions are emitted with `emit_ui_action/3` (async cast). On the cast
  the node encodes the action as a Dylan binary frame and fans it out to
  every pid registered under the `"dylan_transport"` topic in
  `Evoke.Registry` via `Registry.dispatch/3`, each receiving
  `{:dylan_frame, packet}`.

  Crash safety: state is deliberately tiny (id + counter), so a restart
  loses nothing meaningful. Malformed actions are dropped instead of
  crashing the node — one buggy producer must not take down the mesh.
  The supervisor restarts nodes `:transient` (abnormal exits only).
  """
  use GenServer

  alias Evoke.DylanProtocol
  alias Evoke.Telemetry

  @registry Application.compile_env(:evoke, :registry, Evoke.Registry)
  @agent_registry Application.compile_env(:evoke, :agent_registry, Evoke.AgentRegistry)
  @topic Application.compile_env(:evoke, :transport_topic, "dylan_transport")

  defstruct [:id, emitted: 0]

  @type t :: %__MODULE__{id: <<_::128>>, emitted: non_neg_integer()}

  @spec start_link(<<_::128>>) :: GenServer.on_start()
  def start_link(agent_id) when is_binary(agent_id) and byte_size(agent_id) == 16 do
    GenServer.start_link(__MODULE__, agent_id, name: {:via, Registry, {@agent_registry, agent_id}})
  end

  @doc """
  Emits a UI action as a Dylan frame, fanned out to all transports.
  Fire-and-forget: always returns `:ok` once the cast is queued.
  """
  @spec emit_ui_action(<<_::128>>, 0..255, binary()) :: :ok
  def emit_ui_action(agent_id, op_code, payload)
      when is_binary(agent_id) and is_integer(op_code) and is_binary(payload) do
    GenServer.cast({:via, Registry, {@agent_registry, agent_id}}, {:emit_ui_action, op_code, payload})
  end

  @impl true
  def init(agent_id), do: {:ok, %__MODULE__{id: agent_id}}

  @impl true
  def handle_cast({:emit_ui_action, op, payload}, %__MODULE__{} = state)
      when is_integer(op) and op >= 0 and op <= 255 and is_binary(payload) do
    packet = DylanProtocol.encode(state.id, op, payload)
    Telemetry.inc(:frames_encoded)

    Registry.dispatch(@registry, @topic, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:dylan_frame, packet})
    end)

    Telemetry.inc(:frames_dispatched)
    {:noreply, %{state | emitted: state.emitted + 1}}
  end

  # Drop malformed actions instead of crashing the agent.
  def handle_cast({:emit_ui_action, _op, _payload}, state), do: {:noreply, state}
end
