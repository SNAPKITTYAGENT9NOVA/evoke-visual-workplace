defmodule Evoke.TimingTest do
  @moduledoc """
  Agent 4 — SPICE UI Timing & BEAM Latency Verification (ExUnit half).

  Complements Agent 1's `dylan_protocol_test.exs` (codec correctness),
  `backpressure_test.exs` (demand semantics) and `fanout_test.exs`
  (10k fan-out correctness) with the TIMING half of the contract:

    * Dylan encode+decode round-trip: mean < 1 ms/op over 10k iterations.
    * Fan-out: wall-clock split (emit vs. collect) for 1k and 10k agent
      broadcasts into one collector — numbers reported honestly via IO.puts;
      the hard assertion is per-message `DylanProtocol.encode/3` < 1 ms.
    * Backpressure: zero demand -> nothing delivered inside a 50 ms window
      (verified via `Backpressure.stats/0`); positive demand -> full drain,
      timed.

  Every measured number is printed with `IO.puts/1` so `mix test` output is
  the measurement record. Budgets are mapped as a circuit in
  `SPICE_NETLIST.md` (V_beam -> n_fan -> R_sock -> X_codec -> C_buf).

  API shapes below are grounded in Agent 1's as-built app and tests
  (authoritative over the original task memo):
    * `DylanProtocol.decode/1` -> `{:ok, {agent_id, op_code, payload}}`
      (tuple, NOT a map) | `{:error, :crc_mismatch | :corrupted_dylan_packet}`
    * `AgentSupervisor.spawn_agent/0` -> `{:ok, agent_id, pid}`
    * `AgentNode.emit_ui_action/3` -> `:ok`; frames arrive as
      `{:dylan_frame, packet}` messages at the process registered under
      `"dylan_transport"` in `Evoke.Registry`
    * `Backpressure.reset/0`, `enqueue/3`, `request_demand/2`, `stats/0`
  """
  use ExUnit.Case, async: false

  alias Evoke.{DylanProtocol, AgentSupervisor, AgentNode, Backpressure, Telemetry}

  @op_update_avatar_pos 0x0A
  @collect_timeout 30_000

  # ------------------------------------------------------------------
  # 1. Encode/decode round-trip latency
  # ------------------------------------------------------------------

  test "encode/decode round-trip latency: mean < 1ms over 10k iterations" do
    op = @op_update_avatar_pos
    agent_id = :crypto.strong_rand_bytes(16)
    payload = <<100.0::float-32-big, 100.0::float-32-big>>

    # Warm-up: code loading / scheduler costs stay out of the sample.
    Enum.each(1..200, fn _ ->
      packet = DylanProtocol.encode(agent_id, op, payload)
      {:ok, _} = DylanProtocol.decode(packet)
    end)

    n = 10_000
    t0 = System.monotonic_time(:nanosecond)

    Enum.each(1..n, fn _ ->
      packet = DylanProtocol.encode(agent_id, op, payload)
      {:ok, _} = DylanProtocol.decode(packet)
    end)

    t1 = System.monotonic_time(:nanosecond)
    mean_us = (t1 - t0) / n / 1_000

    IO.puts(
      "[timing] encode+decode round-trip: n=#{n} " <>
        "mean=#{Float.round(mean_us, 3)} µs/op (budget 1000 µs)"
    )

    assert mean_us < 1_000,
           "mean round-trip #{Float.round(mean_us, 3)} µs exceeds 1 ms budget"

    # Round-trip correctness anchor on the measured path.
    packet = DylanProtocol.encode(agent_id, op, payload)
    assert {:ok, {^agent_id, ^op, ^payload}} = DylanProtocol.decode(packet)
  end

  # ------------------------------------------------------------------
  # 2. Fan-out latency: N agent nodes -> one collector
  # ------------------------------------------------------------------

  test "fan-out timing: 1k and 10k broadcasts, wall-clock split + per-message encode budget" do
    # The collector identity AgentNode.emit_ui_action/3 delivers to
    # (same wiring as Agent 1's fanout_test).
    {:ok, _} = Registry.register(Evoke.Registry, "dylan_transport", :timing_collector)

    for n <- [1_000, 10_000] do
      ids =
        for _ <- 1..n do
          {:ok, agent_id, _pid} = AgentSupervisor.spawn_agent()
          agent_id
        end

      before = Telemetry.snapshot()

      t0 = System.monotonic_time(:millisecond)

      for {id, i} <- Enum.with_index(ids) do
        :ok = AgentNode.emit_ui_action(id, @op_update_avatar_pos, <<i::32-big>>)
      end

      t_emitted = System.monotonic_time(:millisecond)

      frames =
        for _ <- 1..n do
          receive do
            {:dylan_frame, packet} -> packet
          after
            @collect_timeout -> flunk("timed out collecting #{n} fan-out frames")
          end
        end

      t_collected = System.monotonic_time(:millisecond)

      assert length(frames) == n
      assert Enum.all?(frames, &match?({:ok, _}, DylanProtocol.decode(&1)))

      IO.puts(
        "[timing] fan-out n=#{n}: emit_wall=#{t_emitted - t0}ms " <>
          "collect_wall=#{t_collected - t_emitted}ms total=#{t_collected - t0}ms"
      )

      IO.puts(
        "[timing] fan-out n=#{n}: telemetry before=#{inspect(before)} " <>
          "after=#{inspect(Telemetry.snapshot())}"
      )

      # Hard per-message assertion: each encode is sub-millisecond.
      # (Warmed up first so the max is not a cold-start artifact.)
      Enum.each(1..100, fn _ ->
        _ = DylanProtocol.encode(:crypto.strong_rand_bytes(16), @op_update_avatar_pos, "warm")
      end)

      {total_us, max_us} =
        1..n
        |> Enum.map(fn _ ->
          t_a = System.monotonic_time(:nanosecond)
          _ = DylanProtocol.encode(:crypto.strong_rand_bytes(16), @op_update_avatar_pos, "avatar-pos")
          System.monotonic_time(:nanosecond) - t_a
        end)
        |> Enum.reduce({0, 0}, fn us, {sum, mx} -> {sum + us, max(us, mx)} end)

      mean_us = total_us / n / 1_000
      max_us = div(max_us, 1_000)

      IO.puts(
        "[timing] fan-out n=#{n}: per-message encode " <>
          "mean=#{Float.round(mean_us, 2)}µs max=#{max_us}µs (budget 1000µs)"
      )

      assert max_us < 1_000, "per-message encode max #{max_us}µs exceeded 1 ms"
    end
  end

  # ------------------------------------------------------------------
  # 3. Backpressure timing
  # ------------------------------------------------------------------

  test "backpressure timing: zero demand is silent for 50ms, demand drains" do
    :ok = Backpressure.reset()

    k = 200
    op = @op_update_avatar_pos

    for i <- 1..k do
      :ok = Backpressure.enqueue(:crypto.strong_rand_bytes(16), op, <<i::32-big>>)
    end

    # Zero demand: a 50 ms window must emit nothing.
    t0 = System.monotonic_time(:millisecond)
    Process.sleep(50)
    refute_received {:dylan_frame, _}
    window_ms = System.monotonic_time(:millisecond) - t0

    assert %{queued: ^k, emitted: 0, pending_demand: 0} = Backpressure.stats()

    IO.puts(
      "[timing] backpressure: zero-demand window #{window_ms}ms -> " <>
        "0 frames emitted, #{k} still queued"
    )

    # Positive demand drains everything; time the drain.
    t1 = System.monotonic_time(:millisecond)
    :ok = Backpressure.request_demand(self(), k)

    frames =
      for _ <- 1..k do
        receive do
          {:dylan_frame, packet} -> packet
        after
          5_000 -> flunk("backpressure drain stalled")
        end
      end

    drain_ms = System.monotonic_time(:millisecond) - t1

    assert length(frames) == k
    assert Enum.all?(frames, &match?({:ok, _}, DylanProtocol.decode(&1)))
    assert %{queued: 0, emitted: ^k, pending_demand: 0} = Backpressure.stats()
    refute_received {:dylan_frame, _}

    IO.puts("[timing] backpressure: demand drained #{k}/#{k} frames in #{drain_ms}ms, bus empty")
  end
end
