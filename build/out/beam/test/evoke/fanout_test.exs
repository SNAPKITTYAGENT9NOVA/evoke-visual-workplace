defmodule Evoke.FanoutTest do
  use ExUnit.Case, async: false

  @agent_count 10_000
  @collect_timeout 30_000

  test "10k agent nodes fan out one Dylan frame each to the transport collector" do
    {:ok, _} = Registry.register(Evoke.Registry, "dylan_transport", :fanout_collector)

    ids =
      for _ <- 1..@agent_count do
        {:ok, agent_id, _pid} = Evoke.AgentSupervisor.spawn_agent()
        agent_id
      end

    # Sub-millisecond serialization target: benchmark encode/3 in isolation.
    {encode_us, _} =
      :timer.tc(fn ->
        for _ <- 1..1_000 do
          Evoke.DylanProtocol.encode(:crypto.strong_rand_bytes(16), 0x0A, "avatar-pos")
        end
      end)

    mean_encode_ms = encode_us / 1_000 / 1_000
    IO.puts("dylan encode: mean #{Float.round(mean_encode_ms, 4)} ms/frame over 1000 samples")
    assert mean_encode_ms < 1.0

    wall_start = System.monotonic_time(:millisecond)

    for {id, i} <- Enum.with_index(ids) do
      :ok = Evoke.AgentNode.emit_ui_action(id, 0x0A, <<i::32-big>>)
    end

    frames =
      for _ <- 1..@agent_count do
        receive do
          {:dylan_frame, packet} -> packet
        after
          @collect_timeout -> flunk("timed out waiting for all #{@agent_count} dylan frames")
        end
      end

    wall_ms = System.monotonic_time(:millisecond) - wall_start
    IO.puts("fan-out: #{@agent_count} frames collected in #{wall_ms} ms")

    assert length(frames) == @agent_count

    assert Enum.all?(frames, fn packet ->
             match?({:ok, _}, Evoke.DylanProtocol.decode(packet))
           end)
  end
end
