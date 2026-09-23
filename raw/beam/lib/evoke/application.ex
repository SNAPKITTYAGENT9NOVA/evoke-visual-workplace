defmodule Evoke.Application do
  @moduledoc """
  OTP application entry point for the Dylan message mesh.

  Supervision tree (`:one_for_one`):

      Evoke.Supervisor
      ├── Registry (Evoke.AgentRegistry, keys: :unique)
      │     * agent nodes :via-register under their 16-byte Dylan id
      │       (:via name registration REQUIRES unique keys)
      ├── Registry (Evoke.Registry, keys: :duplicate)
      │     * transports register under the "dylan_transport" topic
      ├── Evoke.Telemetry            — lock-free :counters
      ├── Evoke.AgentSupervisor      — DynamicSupervisor for AgentNodes
      ├── Evoke.Backpressure         — demand-driven frame producer
      └── Evoke.Transport.WebSocket  — RFC 6455 listener (:websocket_port)

  ## Woz fix note

  The original design used ONE duplicate-keys registry for both agent
  `:via` names and transport fan-out. `:via` on a duplicate registry
  raises `ArgumentError` at `start_child` time, so no agent node could
  ever boot. The split above is the minimal correct topology.
  """
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:evoke, :websocket_port, 4002)

    children = [
      {Registry, keys: :unique, name: agent_registry()},
      {Registry, keys: :duplicate, name: registry()},
      Evoke.Telemetry,
      Evoke.AgentSupervisor,
      Evoke.Backpressure,
      {Evoke.Transport.WebSocket, port: port}
    ]

    Logger.info("evoke dylan mesh starting (websocket port #{port})")
    Supervisor.start_link(children, strategy: :one_for_one, name: Evoke.Supervisor)
  end

  defp registry, do: Application.get_env(:evoke, :registry, Evoke.Registry)
  defp agent_registry, do: Application.get_env(:evoke, :agent_registry, Evoke.AgentRegistry)
end
