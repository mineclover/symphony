defmodule SymphonyElixir.ExternalSessionMonitor do
  @moduledoc """
  Generic monitor for external agent sessions.

  Agent-specific adapters provide collection and observer execution; this
  process standardizes pending, success, failure, identity, and persistence
  payloads for the Symphony dashboard.
  """

  use GenServer
  require Logger

  alias SymphonyElixir.{ExternalSessionAdapter, Orchestrator}

  @poll_interval_ms 1_000

  defstruct [
    :adapter,
    :cursor,
    :poll_timer_ref,
    orchestrator: Orchestrator,
    observer: nil
  ]

  @type state :: %__MODULE__{
          adapter: module(),
          cursor: ExternalSessionAdapter.cursor(),
          poll_timer_ref: reference() | nil,
          orchestrator: GenServer.name(),
          observer: (ExternalSessionAdapter.source_session() -> {:ok, map()} | {:error, term()}) | nil
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    adapter = Keyword.fetch!(opts, :adapter)

    %{
      id: {__MODULE__, adapter},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start() | :ignore
  def start_link(opts) do
    adapter = Keyword.fetch!(opts, :adapter)

    if adapter_enabled?(adapter) do
      GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, adapter))
    else
      :ignore
    end
  end

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)

    state = %__MODULE__{
      adapter: adapter,
      cursor: adapter.initial_cursor(),
      orchestrator: Keyword.get(opts, :orchestrator, Orchestrator),
      observer: Keyword.get(opts, :observer)
    }

    {:ok, schedule_poll(state, 0)}
  end

  @impl true
  def handle_info(:poll, %__MODULE__{adapter: adapter, cursor: cursor} = state) do
    {cursor, events} = adapter.read_events(cursor)
    state = %{state | cursor: cursor, poll_timer_ref: nil}

    events
    |> latest_event_per_session()
    |> Enum.each(&inspect_event(&1, state))

    {:noreply, schedule_poll(state, @poll_interval_ms)}
  end

  defp latest_event_per_session(events) do
    events
    |> Enum.reverse()
    |> Enum.uniq_by(&(Map.get(&1, :session_id) || Map.get(&1, "session_id")))
    |> Enum.reverse()
  end

  defp inspect_event(event, %__MODULE__{adapter: adapter} = state) do
    case adapter.source_session(event) do
      {:ok, source_session} ->
        send_detected_summary(state.orchestrator, adapter, source_session)
        run_observer_async(state, source_session)

      {:error, reason} ->
        Logger.debug("Skipping external #{adapter.platform()} session event: #{inspect(reason)}")
    end
  end

  defp send_detected_summary(orchestrator, adapter, source_session) do
    Orchestrator.ingest_session_inspection(
      orchestrator,
      adapter.issue_id(source_session),
      base_summary(adapter, source_session)
      |> Map.merge(%{
        observer: false,
        observer_session: nil,
        observer_turn: nil,
        summary_text: "Detected #{adapter.platform()} session update; observer summary pending.",
        events: []
      })
    )
  end

  defp run_observer_async(%__MODULE__{} = state, source_session) do
    Task.Supervisor.start_child(SymphonyElixir.TaskSupervisor, fn ->
      summary =
        case observer_result(state, source_session) do
          {:ok, observer_summary} ->
            state.adapter
            |> base_summary(source_session)
            |> Map.merge(%{observer: true, events: []})
            |> Map.merge(observer_summary)

          {:error, reason} ->
            state.adapter
            |> base_summary(source_session)
            |> Map.merge(%{
              observer: true,
              observer_session: nil,
              observer_turn: nil,
              summary_text: "Observer summary failed: #{inspect(reason)}",
              error: inspect(reason),
              events: []
            })
        end

      Orchestrator.ingest_session_inspection(state.orchestrator, state.adapter.issue_id(source_session), summary)
    end)
  end

  defp observer_result(%__MODULE__{observer: observer}, source_session) when is_function(observer, 1) do
    observer.(source_session)
  end

  defp observer_result(%__MODULE__{adapter: adapter}, source_session) do
    adapter.observer_summary(source_session, [])
  end

  defp base_summary(adapter, source_session) do
    %{
      inspection_id: adapter.inspection_id(source_session),
      platform: adapter.platform(),
      issue_identifier: adapter.issue_identifier(source_session),
      source_session: adapter.source_identity(source_session),
      cache_analysis: adapter.cache_analysis(source_session),
      status: adapter.status(source_session),
      latest_user_query: adapter.latest_user_query(source_session)
    }
  end

  defp schedule_poll(%__MODULE__{} = state, delay_ms) do
    timer_ref = Process.send_after(self(), :poll, delay_ms)
    %{state | poll_timer_ref: timer_ref}
  end

  defp adapter_enabled?(adapter) do
    if function_exported?(adapter, :enabled?, 0), do: adapter.enabled?(), else: true
  rescue
    _error -> false
  end
end
