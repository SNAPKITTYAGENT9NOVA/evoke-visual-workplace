defmodule Evoke.DylanProtocol do
  @moduledoc """
  Codec for Dylan `<dylan-frame>` wire bytes, shared with
  `raw/dylan/events.dylan`.

  Frame layout (multi-byte integers big-endian):

      Magic[4]     = "DYLN" (0x44 0x59 0x4C 0x4E)
      Agent_ID[16] = Evoke mesh routing id (zeros when unused)
      Opcode[1]
      BodyLen[2]
      Body[N]
      CRC32[4]     = CRC32-IEEE over **Body only**

  The Open Dylan side stores the same logical fields on `<dylan-frame>`
  (magic, opcode, body, crc) without embedding Agent_ID — that field is
  the BEAM mesh extension so `AgentNode` can fan frames by id. CRC scope
  matches Dylan's `crc32-ieee-stub` (body only). Elixir uses a real
  `:erlang.crc32/1` (IEEE); the Dylan function is an educational stub of
  the same polynomial and remains documented as non-production there.

  ## Workplace opcodes (shared with events.dylan)

      0x01  open-file
      0x02  compile-c
      0x03  glow-on
      0x04  glow-off
      0x05  key-enter
      0x06  agent-ask
      0x07  syscall-trace

  ## Legacy Apple Swarm vector ops (still recognized)

      0x0A  update_avatar_pos
      0x0B  draw_window_frame
      0x0C  synthesize_glass_blur
      0x0D  set_window_title
      0x0E  canvas_opacity
  """

  @magic "DYLN"
  @agent_id_len 16
  @max_op 255

  @op_names %{
    0x01 => :open_file,
    0x02 => :compile_c,
    0x03 => :glow_on,
    0x04 => :glow_off,
    0x05 => :key_enter,
    0x06 => :agent_ask,
    0x07 => :syscall_trace,
    0x0A => :update_avatar_pos,
    0x0B => :draw_window_frame,
    0x0C => :synthesize_glass_blur,
    0x0D => :set_window_title,
    0x0E => :canvas_opacity
  }

  @type agent_id :: <<_::128>>
  @type op_code :: 0..255
  @type decode_error :: :crc_mismatch | :corrupted_dylan_packet
  @type frame :: {agent_id(), op_code(), binary()}

  @doc """
  Encodes a DYLN frame. CRC32-IEEE is computed over `payload` only.
  """
  @spec encode(agent_id(), op_code(), binary()) :: binary()
  def encode(agent_id, op_code, payload)
      when is_binary(agent_id) and byte_size(agent_id) == @agent_id_len and is_integer(op_code) and
             op_code >= 0 and op_code <= @max_op and is_binary(payload) do
    header = <<@magic::binary, agent_id::binary, op_code::8, byte_size(payload)::16-big>>
    crc = :erlang.crc32(payload)
    <<header::binary, payload::binary, crc::32-big>>
  end

  @doc """
  Encodes a workplace frame with a zero agent id (pure Dylan interop).
  """
  @spec encode(op_code(), binary()) :: binary()
  def encode(op_code, payload)
      when is_integer(op_code) and op_code >= 0 and op_code <= @max_op and is_binary(payload) do
    encode(<<0::128>>, op_code, payload)
  end

  @doc """
  Decodes a DYLN frame, verifying structure then body CRC32.
  """
  @spec decode(binary()) :: {:ok, frame()} | {:error, decode_error()}
  def decode(
        <<@magic::binary, agent_id::binary-16, op_code::8, payload_len::16-big, rest::binary>>
      ) do
    case rest do
      <<payload::binary-size(payload_len), crc::32-big>> ->
        if :erlang.crc32(payload) == crc do
          {:ok, {agent_id, op_code, payload}}
        else
          {:error, :crc_mismatch}
        end

      _ ->
        {:error, :corrupted_dylan_packet}
    end
  end

  def decode(_), do: {:error, :corrupted_dylan_packet}

  @doc """
  Human-readable name for an opcode; `:unknown_op` when unassigned.
  """
  @spec op_name(integer()) :: atom()
  def op_name(code) when is_integer(code) do
    Map.get(@op_names, code, :unknown_op)
  end

  @doc "Workplace opcode table (Dylan `$op-*` constants)."
  @spec workplace_opcodes() :: %{atom() => op_code()}
  def workplace_opcodes do
    %{
      open_file: 0x01,
      compile_c: 0x02,
      glow_on: 0x03,
      glow_off: 0x04,
      key_enter: 0x05,
      agent_ask: 0x06,
      syscall_trace: 0x07
    }
  end
end
