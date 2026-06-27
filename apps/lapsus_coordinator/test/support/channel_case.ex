defmodule LapsusCoordinatorWeb.ChannelCase do
  @moduledoc """
  Test case for Phoenix channels in the coordinator.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import LapsusCoordinatorWeb.ChannelCase

      @endpoint LapsusCoordinatorWeb.Endpoint
    end
  end

  setup tags do
    # Channel processes run in separate processes, so use shared mode when the
    # case is not async (it isn't — channel + ledger touch the DB).
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(LapsusCoordinator.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
