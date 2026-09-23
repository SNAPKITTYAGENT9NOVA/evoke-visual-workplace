defmodule Evoke.DylanProtocolTest do
  use ExUnit.Case, async: true

  alias Evoke.DylanProtocol

  @workplace_ops [
    {0x01, :open_file},
    {0x02, :compile_c},
    {0x03, :glow_on},
    {0x04, :glow_off},
    {0x05, :key_enter},
    {0x06, :agent_ask},
    {0x07, :syscall_trace}
  ]

  @legacy_ops [
    {0x0A, :update_avatar_pos},
    {0x0B, :draw_window_frame},
    {0x0C, :synthesize_glass_blur},
    {0x0D, :set_window_title},
    {0x0E, :canvas_opacity}
  ]

  test "round-trip encode/decode for workplace and legacy op codes" do
    for {op, name} <- @workplace_ops ++ @legacy_ops do
      agent_id = :crypto.strong_rand_bytes(16)
      payload = :crypto.strong_rand_bytes(64)

      packet = DylanProtocol.encode(agent_id, op, payload)

      assert {:ok, {^agent_id, ^op, ^payload}} = DylanProtocol.decode(packet)
      assert DylanProtocol.op_name(op) == name
      assert <<magic::binary-4, _::binary>> = packet
      assert magic == "DYLN"
    end
  end

  test "encode/2 zero-agent workplace frames round-trip" do
    packet = DylanProtocol.encode(0x01, "hello.c")
    assert {:ok, {<<0::128>>, 0x01, "hello.c"}} = DylanProtocol.decode(packet)
  end

  test "empty and large payloads round-trip" do
    agent_id = :crypto.strong_rand_bytes(16)

    assert {:ok, {^agent_id, 0x0D, <<>>}} =
             agent_id |> DylanProtocol.encode(0x0D, <<>>) |> DylanProtocol.decode()

    big = :crypto.strong_rand_bytes(65_535)

    assert {:ok, {^agent_id, 0x0E, ^big}} =
             agent_id |> DylanProtocol.encode(0x0E, big) |> DylanProtocol.decode()
  end

  test "tampered payload fails CRC verification (CRC covers body only)" do
    agent_id = :crypto.strong_rand_bytes(16)
    packet = DylanProtocol.encode(agent_id, 0x01, "avatar-pos")

    # Header is 23 bytes: 4 magic + 16 agent id + 1 op + 2 length.
    <<head::binary-23, byte, rest::binary>> = packet
    tampered = <<head::binary, Bitwise.bxor(byte, 0xFF)::8, rest::binary>>

    assert {:error, :crc_mismatch} = DylanProtocol.decode(tampered)

    Evoke.Telemetry.inc(:crc_failures)
    assert Evoke.Telemetry.snapshot().crc_failures >= 1
  end

  test "tampered CRC field fails verification" do
    packet = DylanProtocol.encode(:crypto.strong_rand_bytes(16), 0x02, "frame")
    body_len = byte_size(packet) - 4
    <<body::binary-size(body_len), crc::32-big>> = packet
    bad = <<body::binary, Bitwise.bxor(crc, 0x0000_FFFF)::32-big>>

    assert {:error, :crc_mismatch} = DylanProtocol.decode(bad)
  end

  test "truncated packets are structurally corrupt" do
    packet = DylanProtocol.encode(:crypto.strong_rand_bytes(16), 0x03, "blur")

    assert {:error, :corrupted_dylan_packet} = DylanProtocol.decode(<<"DYL">>)
    assert {:error, :corrupted_dylan_packet} = DylanProtocol.decode(<<>>)
    assert {:error, :corrupted_dylan_packet} = DylanProtocol.decode("DYLN")

    truncated = binary_part(packet, 0, byte_size(packet) - 5)
    assert {:error, :corrupted_dylan_packet} = DylanProtocol.decode(truncated)
  end

  test "wrong magic is rejected" do
    packet = DylanProtocol.encode(:crypto.strong_rand_bytes(16), 0x01, "spawn")
    bad_magic = <<"XXXX", binary_part(packet, 4, byte_size(packet) - 4)::binary>>

    assert {:error, :corrupted_dylan_packet} = DylanProtocol.decode(bad_magic)
  end

  test "unknown op codes map to :unknown_op" do
    assert DylanProtocol.op_name(0xFF) == :unknown_op
    assert DylanProtocol.op_name(0x08) == :unknown_op
  end
end
