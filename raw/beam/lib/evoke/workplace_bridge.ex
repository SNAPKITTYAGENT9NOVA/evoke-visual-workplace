defmodule Evoke.WorkplaceBridge do
  @moduledoc """
  Bridges Visual Workplace UI events onto the Evoke BEAM agent mesh.

  Encodes Dylan DYLN frames (see `Evoke.DylanProtocol` / `events.dylan`),
  fans them through `Evoke.AgentNode` → Registry `"dylan_transport"`, and
  decodes inbound packets back to workplace event kinds
  (`:open_file`, `:compile_c`, …) for consumers that call into Dylan's
  `on-dylan-event`.
  """

  alias Evoke.AgentNode
  alias Evoke.AgentSupervisor
  alias Evoke.DylanProtocol

  @type event_kind ::
          :open_file
          | :compile_c
          | :glow_on
          | :glow_off
          | :key_enter
          | :agent_ask
          | :syscall_trace
          | :unknown

  @type workplace_event :: %{
          kind: event_kind(),
          opcode: DylanProtocol.op_code(),
          payload: binary(),
          agent_id: DylanProtocol.agent_id()
        }

  @doc """
  Encodes a workplace UI event as a DYLN binary frame.

  `kind` may be an atom (`:open_file`) or a Dylan-style string/binary
  (`"open-file"` / `"open_file"`).
  """
  @spec encode_event(atom() | String.t(), binary(), DylanProtocol.agent_id()) :: binary()
  def encode_event(kind, body \\ <<>>, agent_id \\ <<0::128>>)

  def encode_event(kind, body, agent_id)
      when is_binary(body) and is_binary(agent_id) and byte_size(agent_id) == 16 do
    opcode = resolve_opcode!(kind)
    DylanProtocol.encode(agent_id, opcode, body)
  end

  @doc """
  Decodes an inbound DYLN frame to a workplace event map.
  """
  @spec decode_event(binary()) :: {:ok, workplace_event()} | {:error, DylanProtocol.decode_error()}
  def decode_event(packet) when is_binary(packet) do
    case DylanProtocol.decode(packet) do
      {:ok, {agent_id, opcode, payload}} ->
        {:ok,
         %{
           kind: kind_from_opcode(opcode),
           opcode: opcode,
           payload: payload,
           agent_id: agent_id
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Encodes `kind`/`body` and fans the frame across the mesh via the given
  agent node (`AgentNode.emit_ui_action/3` → Registry dispatch).
  """
  @spec fan_event(DylanProtocol.agent_id(), atom() | String.t(), binary()) :: :ok
  def fan_event(agent_id, kind, body \\ <<>>)
      when is_binary(agent_id) and byte_size(agent_id) == 16 and is_binary(body) do
    opcode = resolve_opcode!(kind)
    AgentNode.emit_ui_action(agent_id, opcode, body)
  end

  @doc """
  Spawns a fresh mesh agent (if needed) and fans a workplace event.

  Returns `{:ok, agent_id}` after the cast is queued.
  """
  @spec fan_event_new(atom() | String.t(), binary()) :: {:ok, binary()} | {:error, term()}
  def fan_event_new(kind, body \\ <<>>) when is_binary(body) do
    case AgentSupervisor.spawn_agent() do
      {:ok, agent_id, _pid} ->
        :ok = fan_event(agent_id, kind, body)
        {:ok, agent_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Maps a decoded event kind to the Dylan `on-dylan-event` symbol name
  (hyphenated), e.g. `:open_file` → `"open-file"`.
  """
  @spec dylan_symbol(event_kind()) :: String.t()
  def dylan_symbol(:open_file), do: "open-file"
  def dylan_symbol(:compile_c), do: "compile-c"
  def dylan_symbol(:glow_on), do: "glow-on"
  def dylan_symbol(:glow_off), do: "glow-off"
  def dylan_symbol(:key_enter), do: "key-enter"
  def dylan_symbol(:agent_ask), do: "agent-ask"
  def dylan_symbol(:syscall_trace), do: "syscall-trace"
  def dylan_symbol(_), do: "unknown"

  defp resolve_opcode!(kind) when is_integer(kind) and kind >= 0 and kind <= 255, do: kind

  defp resolve_opcode!(kind) when is_atom(kind) do
    Map.get(DylanProtocol.workplace_opcodes(), kind) ||
      raise ArgumentError, "unknown workplace event kind: #{inspect(kind)}"
  end

  defp resolve_opcode!(kind) when is_binary(kind) do
    atom =
      kind
      |> String.replace("-", "_")
      |> String.to_existing_atom()

    resolve_opcode!(atom)
  rescue
    ArgumentError ->
      raise ArgumentError, "unknown workplace event kind: #{inspect(kind)}"
  end

  defp kind_from_opcode(op) do
    case DylanProtocol.op_name(op) do
      :unknown_op -> :unknown
      name -> name
    end
  end
end
