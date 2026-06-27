defmodule LapsusCoordinatorWeb.PeerSocket do
  @moduledoc """
  WebSocket entrypoint for peers, authenticated by Ed25519 signature.

  There is no account/password. A peer proves ownership of its `peer_id` (which
  embeds its public key) by signing `"<peer_id>:<unix_ts>"`. The coordinator
  verifies the signature against the key embedded in the `peer_id` and checks the
  timestamp is fresh (replay window `#{60}s`). See `LapsusCore.Identity` and
  `doc/tech/design.md` §2.1, §3.

  Connect params: `peer_id`, `ts` (unix seconds), `sig` (Base64 signature).
  """
  use Phoenix.Socket

  alias LapsusCore.Identity

  # Max clock skew / replay window in seconds.
  @max_skew 60

  channel "signaling:lobby", LapsusCoordinatorWeb.SignalingChannel

  @impl true
  def connect(%{"peer_id" => peer_id, "ts" => ts, "sig" => sig64}, socket, _connect_info) do
    with {ts_int, ""} <- Integer.parse(to_string(ts)),
         true <- abs(System.os_time(:second) - ts_int) <= @max_skew,
         {:ok, sig} <- Base.decode64(sig64),
         true <- Identity.verify(peer_id, "#{peer_id}:#{ts_int}", sig) do
      {:ok, assign(socket, :peer_id, peer_id)}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "peer_socket:#{socket.assigns.peer_id}"
end
