import Config

config :logger, level: :info

config :evoke,
  # TCP port for the Dylan WebSocket transport listener.
  websocket_port: 4002,
  # Unique-keys registry for agent node :via name registration
  # (one process per 16-byte Dylan id; :via REQUIRES unique keys).
  agent_registry: Evoke.AgentRegistry,
  # Duplicate-keys registry for the transport fan-out topic.
  # Transports register under `transport_topic` to receive
  # {:dylan_frame, packet} via Registry.dispatch/3.
  registry: Evoke.Registry,
  transport_topic: "dylan_transport"
