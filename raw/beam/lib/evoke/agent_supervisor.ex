defmodule Evoke.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor owning all `Evoke.AgentNode` processes.

  `spawn_agent/0` mints a fresh 16-byte Dylan agent id (via
  `:crypto.strong_rand_bytes/1`) and starts the node with
  `restart: :transient` — a node that exits normally (deliberate
  shutdown) stays down; only abnormal exits are restarted.
  """
  use DynamicSupervisor

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts one agent node with a freshly minted 16-byte id.

  Returns `{:ok, agent_id, pid}` so callers can address the node with
  `Evoke.AgentNode.emit_ui_action/3`.
  """
  @spec spawn_agent() :: {:ok, binary(), pid()} | {:error, term()}
  def spawn_agent do
    agent_id = :crypto.strong_rand_bytes(16)

    child_spec = %{
      id: {Evoke.AgentNode, agent_id},
      start: {Evoke.AgentNode, :start_link, [agent_id]},
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> {:ok, agent_id, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
