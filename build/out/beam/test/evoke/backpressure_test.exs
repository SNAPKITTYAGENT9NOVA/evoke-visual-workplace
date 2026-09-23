defmodule Evoke.BackpressureTest do
  use ExUnit.Case, async: false

  alias Evoke.Backpressure

  @receive_timeout 5_000

  setup do
    :ok = Backpressure.reset()
    :ok
  end

  defp agent_id, do: :crypto.strong_rand_bytes(16)

  defp take_frame do
    receive do
      {:dylan_frame, packet} -> packet
    after
      @receive_timeout -> flunk("expected a dylan frame for outstanding demand")
    end
  end

  test "zero demand emits zero frames; demand N delivers exactly N frames" do
    for i <- 1..10 do
      :ok = Backpressure.enqueue(agent_id(), 0x0A, <<i>>)
    end

    # stats/0 is synchronous, so all enqueues are applied: with no demand
    # ever requested, nothing may have been emitted.
    assert %{queued: 10, emitted: 0, pending_demand: 0} = Backpressure.stats()
    refute_received {:dylan_frame, _}

    :ok = Backpressure.request_demand(self(), 4)

    frames = for _ <- 1..4, do: take_frame()

    assert length(frames) == 4
    assert %{queued: 6, emitted: 4, pending_demand: 0} = Backpressure.stats()
    refute_received {:dylan_frame, _}

    for packet <- frames do
      assert {:ok, {_id, 0x0A, _payload}} = Evoke.DylanProtocol.decode(packet)
    end
  end

  test "congestion signal pauses emission and resumes without loss" do
    for i <- 1..6 do
      :ok = Backpressure.enqueue(agent_id(), 0x0B, <<i>>)
    end

    :ok = Backpressure.set_congestion(true)
    :ok = Backpressure.request_demand(self(), 6)

    # Demand is outstanding but congestion holds every frame back.
    assert %{queued: 6, emitted: 0, congested: true} = Backpressure.stats()
    refute_received {:dylan_frame, _}

    :ok = Backpressure.set_congestion(false)

    for _ <- 1..6, do: take_frame()

    assert %{queued: 0, emitted: 6, congested: false} = Backpressure.stats()
    refute_received {:dylan_frame, _}
  end

  test "demand beyond the queue depth leaves residual demand, later jobs flow immediately" do
    :ok = Backpressure.request_demand(self(), 3)
    :ok = Backpressure.enqueue(agent_id(), 0x0C, "one")
    :ok = Backpressure.enqueue(agent_id(), 0x0C, "two")

    assert {:ok, {_, 0x0C, "one"}} = take_frame() |> Evoke.DylanProtocol.decode()
    assert {:ok, {_, 0x0C, "two"}} = take_frame() |> Evoke.DylanProtocol.decode()

    assert %{queued: 0, emitted: 2, pending_demand: 1} = Backpressure.stats()

    :ok = Backpressure.enqueue(agent_id(), 0x0C, "three")
    assert {:ok, {_, 0x0C, "three"}} = take_frame() |> Evoke.DylanProtocol.decode()
    assert %{queued: 0, emitted: 3, pending_demand: 0} = Backpressure.stats()
  end
end
