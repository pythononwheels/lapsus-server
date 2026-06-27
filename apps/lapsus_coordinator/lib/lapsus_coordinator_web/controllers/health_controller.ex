defmodule LapsusCoordinatorWeb.HealthController do
  @moduledoc "Liveness probe for the reverse proxy / deploy health check."
  use LapsusCoordinatorWeb, :controller

  def index(conn, _params), do: text(conn, "ok")
end
