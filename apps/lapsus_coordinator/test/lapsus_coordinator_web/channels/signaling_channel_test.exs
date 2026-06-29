defmodule LapsusCoordinatorWeb.SignalingChannelTest do
  use LapsusCoordinatorWeb.ChannelCase, async: false

  alias LapsusCore.{Identity, Receipt}
  alias LapsusCoordinator.Ledger
  alias LapsusCoordinatorWeb.PeerSocket

  @lobby "signaling:lobby"

  defp connect_peer(identity) do
    ts = System.os_time(:second)
    sig = identity |> Identity.sign("#{identity.peer_id}:#{ts}") |> Base.encode64()

    {:ok, socket} =
      connect(PeerSocket, %{
        "peer_id" => identity.peer_id,
        "ts" => to_string(ts),
        "sig" => sig
      })

    socket
  end

  describe "authentication" do
    test "rejects connection without a valid signature" do
      id = Identity.generate()

      assert :error =
               connect(PeerSocket, %{
                 "peer_id" => id.peer_id,
                 "ts" => to_string(System.os_time(:second)),
                 "sig" => Base.encode64("garbage")
               })
    end

    test "rejects a stale timestamp" do
      id = Identity.generate()
      ts = System.os_time(:second) - 3600
      sig = id |> Identity.sign("#{id.peer_id}:#{ts}") |> Base.encode64()

      assert :error =
               connect(PeerSocket, %{"peer_id" => id.peer_id, "ts" => to_string(ts), "sig" => sig})
    end

    test "accepts a valid signature and assigns the peer_id" do
      id = Identity.generate()
      socket = connect_peer(id)
      assert socket.assigns.peer_id == id.peer_id
    end
  end

  describe "discovery" do
    test "list_providers returns online providers for a model" do
      provider = connect_peer(Identity.generate())
      consumer = connect_peer(Identity.generate())

      {:ok, _, _provider_chan} =
        subscribe_and_join(provider, @lobby, %{"role" => "provider", "models" => ["gemma-4-e2b"]})

      # Ensure the provider's presence is tracked before querying.
      assert_push "presence_state", _

      {:ok, _, consumer_chan} = subscribe_and_join(consumer, @lobby, %{"role" => "consumer"})

      ref = push(consumer_chan, "list_providers", %{"model" => "gemma-4-e2b"})
      assert_reply ref, :ok, %{providers: providers}
      assert Enum.any?(providers, &(&1.peer_id == provider.assigns.peer_id))

      ref2 = push(consumer_chan, "list_providers", %{"model" => "no-such-model"})
      assert_reply ref2, :ok, %{providers: []}
    end
  end

  describe "signaling relay" do
    test "forwards a signal payload to the target peer only" do
      alice = connect_peer(Identity.generate())
      bob = connect_peer(Identity.generate())

      {:ok, _, _bob_chan} = subscribe_and_join(bob, @lobby, %{"role" => "provider"})
      assert_push "presence_state", _

      {:ok, _, alice_chan} = subscribe_and_join(alice, @lobby, %{"role" => "consumer"})
      assert_push "presence_state", _

      ref =
        push(alice_chan, "signal", %{
          "to" => bob.assigns.peer_id,
          "kind" => "offer",
          "data" => "v=0..."
        })

      assert_reply ref, :ok

      assert_push "signal", payload
      assert payload["from"] == alice.assigns.peer_id
      assert payload["kind"] == "offer"
      assert payload["data"] == "v=0..."
    end
  end

  describe "billing (submit_receipt)" do
    defp receipt(consumer_id, provider_id, cc) do
      %{
        "job_id" => "job-#{System.unique_integer([:positive])}",
        "consumer_id" => consumer_id,
        "provider_id" => provider_id,
        "model" => "gemma-4-e2b",
        "in_tokens" => 29,
        "out_tokens" => 287,
        "model_weight" => 2,
        "cc" => cc
      }
    end

    test "books a job when both signatures verify and submitter is the consumer" do
      consumer = Identity.generate()
      provider = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(consumer), @lobby, %{"role" => "consumer"})

      r = receipt(consumer.peer_id, provider.peer_id, 30)

      ref =
        push(chan, "submit_receipt", %{
          "receipt" => r,
          "provider_sig" => Receipt.sign(provider, r),
          "consumer_sig" => Receipt.sign(consumer, r)
        })

      assert_reply ref, :ok, %{balance: balance}
      assert balance == Ledger.faucet_cc() - 30
      assert Ledger.balance(provider.peer_id) == Ledger.faucet_cc() + 30
    end

    test "rejects a receipt with an invalid signature" do
      consumer = Identity.generate()
      provider = Identity.generate()
      other = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(consumer), @lobby, %{"role" => "consumer"})

      r = receipt(consumer.peer_id, provider.peer_id, 30)

      ref =
        push(chan, "submit_receipt", %{
          "receipt" => r,
          # signed by the wrong identity
          "provider_sig" => Receipt.sign(other, r),
          "consumer_sig" => Receipt.sign(consumer, r)
        })

      assert_reply ref, :error, %{reason: "invalid_provider_sig"}
    end

    test "rejects when the submitter is not the receipt's consumer" do
      submitter = Identity.generate()
      consumer = Identity.generate()
      provider = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(submitter), @lobby, %{"role" => "consumer"})

      r = receipt(consumer.peer_id, provider.peer_id, 30)

      ref =
        push(chan, "submit_receipt", %{
          "receipt" => r,
          "provider_sig" => Receipt.sign(provider, r),
          "consumer_sig" => Receipt.sign(consumer, r)
        })

      assert_reply ref, :error, %{reason: "invalid_submitter"}
    end

    test "does not double-book the same job_id" do
      consumer = Identity.generate()
      provider = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(consumer), @lobby, %{"role" => "consumer"})

      r = receipt(consumer.peer_id, provider.peer_id, 30)

      payload = %{
        "receipt" => r,
        "provider_sig" => Receipt.sign(provider, r),
        "consumer_sig" => Receipt.sign(consumer, r)
      }

      ref1 = push(chan, "submit_receipt", payload)
      assert_reply ref1, :ok, _

      ref2 = push(chan, "submit_receipt", payload)
      assert_reply ref2, :error, %{reason: "duplicate_job"}

      # Charged only once.
      assert Ledger.balance(consumer.peer_id) == Ledger.faucet_cc() - 30
    end
  end

  describe "pre-flight funds check (check_funds)" do
    test "ok: true and materializes the faucet for a brand-new consumer" do
      consumer = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(consumer), @lobby, %{"role" => "consumer"})

      ref = push(chan, "check_funds", %{"consumer_id" => consumer.peer_id, "cc" => 10})
      assert_reply ref, :ok, %{ok: true, balance: balance}
      # The starter faucet was granted on first check, so a newcomer can try the network.
      assert balance == Ledger.faucet_cc()
    end

    test "ok: false when the estimate exceeds the balance" do
      consumer = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(consumer), @lobby, %{"role" => "consumer"})

      ref = push(chan, "check_funds", %{"consumer_id" => consumer.peer_id, "cc" => Ledger.faucet_cc() + 1})
      assert_reply ref, :ok, %{ok: false}
    end

    test "rejects a malformed request" do
      consumer = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(consumer), @lobby, %{"role" => "consumer"})

      ref = push(chan, "check_funds", %{"consumer_id" => consumer.peer_id, "cc" => -1})
      assert_reply ref, :error, %{reason: "bad_request"}
    end
  end

  describe "escrow reserve" do
    test "reserves credits and reports balance; available drops" do
      provider = Identity.generate()
      consumer = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(provider), @lobby, %{"role" => "provider"})

      ref = push(chan, "reserve", %{"consumer_id" => consumer.peer_id, "request_id" => "job-r1", "cc" => 10})
      assert_reply ref, :ok, %{ok: true, balance: balance}
      assert balance == Ledger.faucet_cc()
      assert Ledger.held(consumer.peer_id) == 10
      assert Ledger.available(consumer.peer_id) == Ledger.faucet_cc() - 10
    end

    test "fails when the estimate exceeds available" do
      provider = Identity.generate()
      consumer = Identity.generate()
      {:ok, _, chan} = subscribe_and_join(connect_peer(provider), @lobby, %{"role" => "provider"})

      ref =
        push(chan, "reserve", %{
          "consumer_id" => consumer.peer_id,
          "request_id" => "job-r2",
          "cc" => Ledger.faucet_cc() + 1
        })

      assert_reply ref, :error, %{reason: "insufficient_funds"}
    end
  end
end
