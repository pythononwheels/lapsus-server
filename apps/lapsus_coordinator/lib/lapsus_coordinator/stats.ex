defmodule LapsusCoordinator.Stats do
  @moduledoc """
  Usage aggregation for the dashboards, derived from the `jobs` table.

  Records a row per booked job, and aggregates per peer: daily in/out tokens over a
  window, per-model usage, and totals. Aggregation is done in Elixir (modest data,
  SQLite-friendly).
  """
  import Ecto.Query

  alias LapsusCoordinator.Repo
  alias LapsusCoordinator.Stats.Job

  @doc "Record a booked job from a receipt map."
  def record(receipt) do
    %Job{}
    |> Job.changeset(%{
      provider_id: receipt["provider_id"],
      consumer_id: receipt["consumer_id"],
      model: receipt["model"],
      in_tokens: receipt["in_tokens"],
      out_tokens: receipt["out_tokens"],
      cc: receipt["cc"],
      ok: true
    })
    |> Repo.insert()
  end

  @doc "Usage as a provider (jobs served), shaped for the dashboard."
  def provider_usage(peer_id, days \\ 7), do: usage(:provider_id, peer_id, days)

  @doc "Usage as a consumer (requests sent), shaped for the dashboard."
  def consumer_usage(peer_id, days \\ 7), do: usage(:consumer_id, peer_id, days)

  @doc "Count of jobs served as a provider today (persistent — survives restarts)."
  def served_today(peer_id) do
    start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    Repo.one(
      from j in Job, where: j.provider_id == ^peer_id and j.inserted_at >= ^start, select: count(j.id)
    ) || 0
  end

  @doc "All-time count of jobs served as a provider (persistent)."
  def served_total(peer_id) do
    Repo.one(from j in Job, where: j.provider_id == ^peer_id, select: count(j.id)) || 0
  end

  # --- internals ---

  defp usage(field, peer_id, days) do
    today = Date.utc_today()
    start_date = Date.add(today, -(days - 1))
    since = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")

    rows =
      Repo.all(
        from j in Job,
          where: field(j, ^field) == ^peer_id and j.inserted_at >= ^since,
          select: %{date: fragment("date(?)", j.inserted_at), model: j.model, in: j.in_tokens, out: j.out_tokens, cc: j.cc}
      )

    %{
      days: bucketed_series(rows, start_date, today, days),
      by_model: by_model(rows),
      totals: totals(rows)
    }
  end

  # Daily series over the window, then chunked so a long range never shows more
  # than ~30 bars (week → daily; year → ~12-day buckets). Each bucket is labelled
  # with its first date.
  defp bucketed_series(rows, start_date, today, days) do
    daily = daily_series(rows, start_date, today)
    bucket_size = max(1, ceil(days / 30))

    if bucket_size == 1 do
      daily
    else
      daily
      |> Enum.chunk_every(bucket_size)
      |> Enum.map(fn chunk ->
        %{date: hd(chunk).date, in: sum(chunk, :in), out: sum(chunk, :out)}
      end)
    end
  end

  defp daily_series(rows, start_date, today) do
    by_date =
      Enum.group_by(rows, &to_string(&1.date))
      |> Map.new(fn {d, rs} -> {d, {sum(rs, :in), sum(rs, :out)}} end)

    Date.range(start_date, today)
    |> Enum.map(fn d ->
      key = Date.to_iso8601(d)
      {i, o} = Map.get(by_date, key, {0, 0})
      %{date: key, in: i, out: o}
    end)
  end

  defp by_model(rows) do
    rows
    |> Enum.group_by(& &1.model)
    |> Enum.map(fn {model, rs} ->
      %{model: model, jobs: length(rs), in: sum(rs, :in), out: sum(rs, :out), cc: sum(rs, :cc)}
    end)
    |> Enum.sort_by(&(-&1.out))
  end

  defp totals(rows) do
    %{jobs: length(rows), in: sum(rows, :in), out: sum(rows, :out), cc: sum(rows, :cc)}
  end

  defp sum(rows, key), do: Enum.reduce(rows, 0, &((&1[key] || 0) + &2))
end
