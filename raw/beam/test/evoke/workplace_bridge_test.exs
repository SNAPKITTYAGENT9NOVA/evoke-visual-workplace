defmodule Evoke.WorkplaceBridgeTest do
  use ExUnit.Case, async: false

  alias Evoke.WorkplaceBridge

  test "encode_event / decode_event round-trip for every workplace kind" do
    for kind <- [:open_file, :compile_c, :glow_on, :glow_off, :key_enter, :agent_ask, :syscall_trace] do
      packet = WorkplaceBridge.encode_event(kind, "payload-#{kind}")
      assert {:ok, event} = WorkplaceBridge.decode_event(packet)
      assert event.kind == kind
      assert event.payload == "payload-#{kind}"
      assert WorkplaceBridge.dylan_symbol(kind) =~ "-"
    end
  end

  test "hyphenated Dylan kind names encode" do
    packet = WorkplaceBridge.encode_event("open-file", "hello.c")
    assert {:ok, %{kind: :open_file, payload: "hello.c"}} = WorkplaceBridge.decode_event(packet)
  end

  test "fan_event delivers DYLN frame to transport collector" do
    {:ok, _} = Registry.register(Evoke.Registry, "dylan_transport", :bridge_collector)
    {:ok, agent_id, _pid} = Evoke.AgentSupervisor.spawn_agent()

    :ok = WorkplaceBridge.fan_event(agent_id, :glow_on, "hello.c")

    assert_receive {:dylan_frame, packet}, 5_000
    assert {:ok, %{kind: :glow_on, payload: "hello.c", agent_id: ^agent_id}} =
             WorkplaceBridge.decode_event(packet)
  end
end
