defmodule SymphonyElixir.ExternalSessionMonitorTest do
  use SymphonyElixir.TestSupport

  defmodule FakeExternalAdapter do
    @behaviour SymphonyElixir.ExternalSessionAdapter

    def platform, do: :fake_cached_cli
    def enabled?, do: true
    def initial_cursor, do: file_size()

    def read_events(offset) do
      case File.read(events_file()) do
        {:ok, contents} ->
          size = byte_size(contents)
          offset = min(offset, size)

          events =
            contents
            |> binary_part(offset, size - offset)
            |> String.split("\n", trim: true)
            |> Enum.map(&Jason.decode!/1)
            |> Enum.map(fn event ->
              %{session_id: Map.fetch!(event, "session_id"), latest_user_query: Map.fetch!(event, "text")}
            end)

          {size, events}

        {:error, _reason} ->
          {0, []}
      end
    end

    def source_session(%{session_id: session_id, latest_user_query: latest_user_query}) do
      {:ok,
       %{
         id: session_id,
         latest_user_query: latest_user_query,
         status: "active_recently",
         cache_analysis: %{cache_hit?: true, cached_input_tokens: 90, input_tokens: 100, cache_hit_ratio: 0.9}
       }}
    end

    def source_identity(source_session), do: %{id: source_session.id}
    def issue_id(source_session), do: "fake:#{source_session.id}"
    def issue_identifier(source_session), do: "FAKE-#{source_session.id}"
    def inspection_id(source_session), do: "fake:#{source_session.id}:latest"
    def cache_analysis(source_session), do: source_session.cache_analysis
    def latest_user_query(source_session), do: source_session.latest_user_query
    def status(source_session), do: source_session.status

    def observer_summary(source_session, _opts) do
      {:ok,
       %{
         observer_session: %{id: "#{source_session.id}-observer", clone_strategy: :fake_clone},
         observer_turn: %{turn_id: "#{source_session.id}-observer-turn"},
         summary_text: "fake observer summary for #{source_session.latest_user_query}",
         observer_cache_analysis: %{cache_hit?: true, cached_input_tokens: 80, input_tokens: 100, cache_hit_ratio: 0.8},
         events: []
       }}
    end

    defp file_size do
      case File.stat(events_file()) do
        {:ok, %File.Stat{size: size}} -> size
        _ -> 0
      end
    end

    defp events_file, do: Application.fetch_env!(:symphony_elixir, :fake_external_events_file)
  end

  test "generic external session monitor standardizes non-Codex adapter summaries" do
    test_root = Path.join(System.tmp_dir!(), "symphony-external-monitor-#{System.unique_integer([:positive])}")
    events_file = Path.join(test_root, "events.jsonl")
    store_file = Path.join(test_root, "inspections.jsonl")

    Application.put_env(:symphony_elixir, :fake_external_events_file, events_file)
    Application.put_env(:symphony_elixir, :session_inspection_store_file, store_file)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :fake_external_events_file)
      Application.delete_env(:symphony_elixir, :session_inspection_store_file)
      File.rm_rf(test_root)
    end)

    File.mkdir_p!(test_root)
    File.write!(events_file, "")

    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "none", session_inspection_enabled: true)

    orchestrator_name = Module.concat(__MODULE__, :GenericExternalOrchestrator)
    {:ok, orchestrator_pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(orchestrator_pid) do
        Process.exit(orchestrator_pid, :normal)
      end
    end)

    {:ok, monitor_pid} =
      SymphonyElixir.ExternalSessionMonitor.start_link(
        name: Module.concat(__MODULE__, :GenericExternalMonitor),
        adapter: FakeExternalAdapter,
        orchestrator: orchestrator_name
      )

    on_exit(fn ->
      if Process.alive?(monitor_pid) do
        Process.exit(monitor_pid, :normal)
      end
    end)

    File.write!(events_file, Jason.encode!(%{session_id: "A1", text: "first command"}) <> "\n", [:append])

    assert_eventually(fn ->
      snapshot = Orchestrator.snapshot(orchestrator_name, 1_000)
      inspections = Enum.filter(snapshot.session_inspections, &(map_get(&1, :issue_id) == "fake:A1"))
      inspection = List.first(inspections)

      length(inspections) == 1 and
        map_get(inspection, :platform) == :fake_cached_cli and
        map_get(inspection, :summary_text) == "fake observer summary for first command" and
        map_get(inspection, :observer_cache_analysis).cache_hit? == true
    end)

    File.write!(events_file, Jason.encode!(%{session_id: "A1", text: "second command"}) <> "\n", [:append])

    assert_eventually(fn ->
      snapshot = Orchestrator.snapshot(orchestrator_name, 1_000)
      inspections = Enum.filter(snapshot.session_inspections, &(map_get(&1, :issue_id) == "fake:A1"))

      length(inspections) == 1 and
        map_get(List.first(inspections), :summary_text) == "fake observer summary for second command"
    end)

    assert [stored] = Map.fetch!(SymphonyElixir.SessionInspectionStore.load(), "fake:A1")
    assert stored["platform"] == "fake_cached_cli"
    assert stored["summary_text"] == "fake observer summary for second command"
    assert get_in(stored, ["observer_cache_analysis", "cache_hit?"]) == true
  end

  defp map_get(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(100)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition not met in time")
end
