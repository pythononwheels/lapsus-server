defmodule LapsusCoordinatorWeb.SignalingChannel do
  @moduledoc """
  Discovery + WebRTC signaling relay.

  All peers join the single `"signaling:lobby"` topic. The channel does three
  things — and never touches inference traffic (that goes P2P, §2):

    1. **Presence** — track the peer with its metadata (role, offered models).
    2. **Discovery** — `"list_providers"` returns online providers for a model.
    3. **Signaling relay** — `"signal"` forwards a WebRTC SDP/ICE payload to a
       specific target peer, so the two can establish a direct connection.

  Directed delivery uses a per-peer PubSub topic `"peer:<peer_id>"` that each
  peer's channel process subscribes to on join.
  """
  use Phoenix.Channel

  alias LapsusCoordinator.{Ledger, Presence, Stats}
  alias LapsusCore.Receipt
  alias Phoenix.PubSub

  @lobby "signaling:lobby"
  @pubsub LapsusCoordinator.PubSub

  @impl true
  def join(@lobby, params, socket) do
    socket = assign(socket, :meta, peer_meta(params))
    PubSub.subscribe(@pubsub, "peer:#{socket.assigns.peer_id}")
    send(self(), :after_join)
    {:ok, %{peer_id: socket.assigns.peer_id}, socket}
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "unknown topic"}}

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _ref} = Presence.track(socket, socket.assigns.peer_id, socket.assigns.meta)
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # A directed signaling message arrived for us → push to our client.
  def handle_info({:signal, from, payload}, socket) do
    push(socket, "signal", Map.put(payload, "from", from))
    {:noreply, socket}
  end

  @impl true
  # Relay a WebRTC SDP/ICE payload to a target peer.
  def handle_in("signal", %{"to" => to} = msg, socket) do
    payload = Map.take(msg, ["to", "kind", "data"])
    PubSub.broadcast(@pubsub, "peer:#{to}", {:signal, socket.assigns.peer_id, payload})
    {:reply, :ok, socket}
  end

  # Book a completed job: requires a receipt signed by BOTH peers, and the
  # submitter must be the consumer (the party that pays). See LapsusCore.Receipt.
  def handle_in(
        "submit_receipt",
        %{"receipt" => r, "provider_sig" => psig, "consumer_sig" => csig},
        socket
      ) do
    cc = r["cc"]

    with {:submitter, true} <- {:submitter, socket.assigns.peer_id == r["consumer_id"]},
         {:cc, true} <- {:cc, is_integer(cc) and cc > 0},
         {:provider_sig, true} <- {:provider_sig, Receipt.verify(r["provider_id"], r, psig)},
         {:consumer_sig, true} <- {:consumer_sig, Receipt.verify(r["consumer_id"], r, csig)},
         {:ok, _entry} <- Ledger.record_job(r["consumer_id"], r["provider_id"], cc, r["job_id"]) do
      Stats.record(r)
      {:reply, {:ok, %{balance: Ledger.balance(r["consumer_id"])}}, socket}
    else
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
      {step, false} -> {:reply, {:error, %{reason: "invalid_#{step}"}}, socket}
    end
  end

  # Balance + earned-today + jobs-served-today for the requesting peer (provider dashboard).
  def handle_in("stats", _payload, socket) do
    id = socket.assigns.peer_id

    reply =
      Ledger.stats(id)
      |> Map.put(:served_today, Stats.served_today(id))
      |> Map.put(:served_total, Stats.served_total(id))

    {:reply, {:ok, reply}, socket}
  end

  # Usage series (provider + consumer view) for the dashboards, over the requested
  # window (days). Clamped to a sane range; default a week.
  def handle_in("usage", payload, socket) do
    id = socket.assigns.peer_id
    days = (payload["days"] || 7) |> max(1) |> min(3660)

    {:reply,
     {:ok,
      %{
        provider: Stats.provider_usage(id, days),
        consumer: Stats.consumer_usage(id, days),
        balance: Ledger.balance(id)
      }}, socket}
  end

  # A provider changed which models it advertises (+ per-model caps) → update meta.
  def handle_in("update_models", %{"models" => models} = payload, socket) do
    caps = payload["caps"] || %{}

    Presence.update(socket, socket.assigns.peer_id, fn meta ->
      meta |> Map.put(:models, models) |> Map.put(:caps, caps)
    end)

    {:reply, :ok, socket}
  end

  # All models currently offered across the network (distinct), with provider
  # counts and aggregated capabilities (max context length, any-multimodal).
  def handle_in("models", _payload, socket) do
    self_id = socket.assigns.peer_id

    models =
      socket
      |> Presence.list()
      |> Enum.reject(fn {peer_id, _} -> peer_id == self_id end)
      |> Enum.flat_map(fn {_peer_id, %{metas: metas}} ->
        metas
        |> Enum.filter(&(&1[:role] == "provider"))
        |> Enum.flat_map(fn meta ->
          caps = meta[:caps] || %{}
          Enum.map(meta[:models] || [], fn name -> {name, caps[name] || %{}} end)
        end)
      end)
      |> Enum.group_by(fn {name, _c} -> name end, fn {_name, c} -> c end)
      |> Enum.map(fn {model, caps_list} ->
        %{
          model: model,
          providers: length(caps_list),
          ctx: caps_list |> Enum.map(& &1["ctx"]) |> Enum.reject(&is_nil/1) |> max_or_nil(),
          multimodal: Enum.any?(caps_list, &(&1["vision"] == true))
        }
      end)
      |> Enum.sort_by(&{-&1.providers, &1.model})

    {:reply, {:ok, %{models: models}}, socket}
  end

  # Find online providers offering a given model (never the caller itself).
  # `min_ctx` (optional) filters out providers whose advertised context window is
  # known to be smaller than the request needs.
  def handle_in("list_providers", %{"model" => model} = payload, socket) do
    self_id = socket.assigns.peer_id
    min_ctx = payload["min_ctx"]

    providers =
      socket
      |> Presence.list()
      |> Enum.reject(fn {peer_id, _} -> peer_id == self_id end)
      |> Enum.flat_map(fn {peer_id, %{metas: metas}} ->
        Enum.filter(metas, &provider_offering?(&1, model))
        |> Enum.map(fn meta ->
          %{peer_id: peer_id, capacity: meta[:capacity], ctx: get_in(meta, [:caps, model, "ctx"])}
        end)
      end)
      |> Enum.filter(&ctx_ok?(&1.ctx, min_ctx))

    {:reply, {:ok, %{providers: providers}}, socket}
  end

  # --- internals ---

  defp peer_meta(params) do
    %{
      role: params["role"] || "consumer",
      models: List.wrap(params["models"]),
      caps: params["caps"] || %{},
      capacity: params["capacity"]
    }
  end

  defp max_or_nil([]), do: nil
  defp max_or_nil(list), do: Enum.max(list)

  # Keep a provider unless we know its context window is too small. Unknown ctx
  # (older providers / models that don't report it) is allowed through.
  defp ctx_ok?(_ctx, nil), do: true
  defp ctx_ok?(nil, _min), do: true
  defp ctx_ok?(ctx, min) when is_integer(ctx) and is_integer(min), do: ctx >= min
  defp ctx_ok?(_ctx, _min), do: true

  defp provider_offering?(%{role: "provider", models: models}, model), do: model in models
  defp provider_offering?(_meta, _model), do: false
end
