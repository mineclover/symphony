defmodule SymphonyElixir.CodexExternalSessionMonitorTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Codex.{ExternalSessionMonitor, SessionLog}

  test "session log reads new history entries and extracts source session metadata" do
    test_root = Path.join(System.tmp_dir!(), "symphony-codex-log-#{System.unique_integer([:positive])}")
    codex_home = Path.join(test_root, ".codex")
    session_id = "019df625-458c-7370-baa3-418eea4c822e"
    session_file = session_file(codex_home, session_id)
    history_file = Path.join(codex_home, "history.jsonl")

    Application.put_env(:symphony_elixir, :codex_home, codex_home)
    Application.put_env(:symphony_elixir, :codex_history_file, history_file)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :codex_home)
      Application.delete_env(:symphony_elixir, :codex_history_file)
      File.rm_rf(test_root)
    end)

    File.mkdir_p!(Path.dirname(session_file))
    File.mkdir_p!(Path.dirname(history_file))

    File.write!(history_file, Jason.encode!(%{session_id: session_id, ts: 1, text: "남은 작업 확인"}) <> "\n")

    File.write!(session_file, Enum.join(session_events(), "\n") <> "\n")

    assert {byte_size, [entry]} = SessionLog.read_history_entries(0)
    assert byte_size > 0
    assert entry.session_id == session_id
    assert entry.latest_user_query == "남은 작업 확인"

    assert {:ok, source_session} = SessionLog.source_session(entry)
    assert source_session.id == session_id
    assert source_session.cwd == "/tmp/source-workspace"
    assert source_session.model == "gpt-5.5"
    assert source_session.model_provider == "openai"
    assert source_session.latest_user_query == "남은 작업 확인"
    assert source_session.cache_analysis.cached_input_tokens == 750
    assert source_session.cache_analysis.input_tokens == 1000
    assert source_session.cache_analysis.cache_hit_ratio == 0.75
    assert source_session.transcript_excerpt =~ "latest_user_query: 남은 작업 확인"
    assert SessionLog.observer_prompt(source_session) =~ SessionLog.observer_marker()
    assert SessionLog.observer_prompt(source_session) =~ "Source model: gpt-5.5"
  end

  test "external session monitor ingests only new Codex history lines" do
    test_root = Path.join(System.tmp_dir!(), "symphony-codex-monitor-#{System.unique_integer([:positive])}")
    codex_home = Path.join(test_root, ".codex")
    history_file = Path.join(codex_home, "history.jsonl")
    store_file = Path.join(test_root, "inspections.jsonl")
    session_id = "019df62c-27ae-7af0-901d-72f5137564f2"
    session_file = session_file(codex_home, session_id)

    Application.put_env(:symphony_elixir, :codex_home, codex_home)
    Application.put_env(:symphony_elixir, :codex_history_file, history_file)
    Application.put_env(:symphony_elixir, :session_inspection_store_file, store_file)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :codex_home)
      Application.delete_env(:symphony_elixir, :codex_history_file)
      Application.delete_env(:symphony_elixir, :session_inspection_store_file)
      File.rm_rf(test_root)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "none",
      session_inspection_enabled: true
    )

    File.mkdir_p!(Path.dirname(session_file))
    File.mkdir_p!(Path.dirname(history_file))
    File.write!(history_file, "")
    File.write!(session_file, Enum.join(session_events(), "\n") <> "\n")

    File.write!(
      store_file,
      Enum.join(
        [
          Jason.encode!(old_external_summary(session_id, "old-pending", "Detected Codex session update; observer summary pending.")),
          Jason.encode!(old_external_summary(session_id, "old-failed", "Observer summary failed: previous error"))
        ],
        "\n"
      ) <> "\n"
    )

    orchestrator_name = Module.concat(__MODULE__, :ExternalMonitorOrchestrator)
    {:ok, orchestrator_pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(orchestrator_pid) do
        Process.exit(orchestrator_pid, :normal)
      end
    end)

    observer = fn source_session ->
      assert source_session.model == "gpt-5.5"

      {:ok,
       %{
         observer_session: %{id: "observer-session"},
         observer_turn: %{turn_id: "observer-turn"},
         summary_text: "observer summary for #{source_session.latest_user_query}",
         events: []
       }}
    end

    {:ok, monitor_pid} =
      ExternalSessionMonitor.start_link(
        name: Module.concat(__MODULE__, :ExternalMonitor),
        orchestrator: orchestrator_name,
        observer: observer
      )

    on_exit(fn ->
      if Process.alive?(monitor_pid) do
        Process.exit(monitor_pid, :normal)
      end
    end)

    File.write!(history_file, Jason.encode!(%{session_id: session_id, ts: 2, text: "남은 작업 확인"}) <> "\n", [:append])

    assert_eventually(fn ->
      snapshot = Orchestrator.snapshot(orchestrator_name, 1_000)
      inspections = Enum.filter(snapshot.session_inspections, &(map_get(&1, :issue_id) == "codex:#{session_id}"))

      length(inspections) == 1 and
        map_get(List.first(inspections), :summary_text) =~ "observer summary for 남은 작업 확인" and
        map_get(List.first(inspections), :observer) == true
    end)

    assert [stored] = Map.fetch!(SymphonyElixir.SessionInspectionStore.load(), "codex:#{session_id}")
    assert stored["summary_text"] =~ "observer summary for 남은 작업 확인"
    assert stored["observer"] == true

    File.write!(history_file, Jason.encode!(%{session_id: session_id, ts: 3, text: "새 명령 확인"}) <> "\n", [:append])

    assert_eventually(fn ->
      snapshot = Orchestrator.snapshot(orchestrator_name, 1_000)
      inspections = Enum.filter(snapshot.session_inspections, &(map_get(&1, :issue_id) == "codex:#{session_id}"))

      length(inspections) == 1 and
        map_get(List.first(inspections), :summary_text) =~ "observer summary for 새 명령 확인" and
        map_get(List.first(inspections), :latest_user_query) == "새 명령 확인"
    end)

    assert [updated] = Map.fetch!(SymphonyElixir.SessionInspectionStore.load(), "codex:#{session_id}")
    assert updated["summary_text"] =~ "observer summary for 새 명령 확인"
    assert updated["latest_user_query"] == "새 명령 확인"
  end

  test "external session monitor forks the collected Codex rollout path before summarizing" do
    test_root = Path.join(System.tmp_dir!(), "symphony-codex-monitor-fork-#{System.unique_integer([:positive])}")
    codex_home = Path.join(test_root, ".codex")
    history_file = Path.join(codex_home, "history.jsonl")
    store_file = Path.join(test_root, "inspections.jsonl")
    workspace_root = Path.join(test_root, "workspaces")
    codex_binary = Path.join(test_root, "fake-codex")
    trace_file = Path.join(test_root, "codex-observer.trace")
    session_id = "019df62d-458c-7370-baa3-418eea4c8999"
    session_file = session_file(codex_home, session_id)
    previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

    Application.put_env(:symphony_elixir, :codex_home, codex_home)
    Application.put_env(:symphony_elixir, :codex_history_file, history_file)
    Application.put_env(:symphony_elixir, :session_inspection_store_file, store_file)
    System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)

    on_exit(fn ->
      restore_env("SYMP_TEST_CODEx_TRACE", previous_trace)
      Application.delete_env(:symphony_elixir, :codex_home)
      Application.delete_env(:symphony_elixir, :codex_history_file)
      Application.delete_env(:symphony_elixir, :session_inspection_store_file)
      File.rm_rf(test_root)
    end)

    File.mkdir_p!(Path.dirname(session_file))
    File.mkdir_p!(Path.dirname(history_file))
    File.write!(history_file, "")
    File.write!(session_file, Enum.join(session_events(), "\n") <> "\n")
    File.write!(codex_binary, fake_observer_codex_script())
    File.chmod!(codex_binary, 0o755)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "none",
      workspace_root: workspace_root,
      codex_command: "#{codex_binary} app-server",
      session_inspection_enabled: true
    )

    orchestrator_name = Module.concat(__MODULE__, :ExternalMonitorForkOrchestrator)
    {:ok, orchestrator_pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(orchestrator_pid) do
        Process.exit(orchestrator_pid, :normal)
      end
    end)

    {:ok, monitor_pid} =
      ExternalSessionMonitor.start_link(
        name: Module.concat(__MODULE__, :ExternalMonitorFork),
        orchestrator: orchestrator_name
      )

    on_exit(fn ->
      if Process.alive?(monitor_pid) do
        Process.exit(monitor_pid, :normal)
      end
    end)

    File.write!(history_file, Jason.encode!(%{session_id: session_id, ts: 2, text: "남은 작업 확인"}) <> "\n", [:append])

    assert_eventually(fn ->
      snapshot = Orchestrator.snapshot(orchestrator_name, 1_000)
      inspections = Enum.filter(snapshot.session_inspections, &(map_get(&1, :issue_id) == "codex:#{session_id}"))

      length(inspections) == 1 and
        map_get(List.first(inspections), :summary_text) == "observer final summary" and
        map_get(map_get(List.first(inspections), :observer_session), :clone_strategy) == :codex_thread_fork_path
    end)

    trace = File.read!(trace_file)
    lines = String.split(trace, "\n", trim: true)

    assert Enum.any?(lines, fn line ->
             if String.starts_with?(line, "JSON:") do
               payload = line |> String.trim_leading("JSON:") |> Jason.decode!()

               payload["method"] == "thread/start" &&
                 get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                 get_in(payload, ["params", "sandbox"]) == "read-only"
             else
               false
             end
           end)

    assert Enum.any?(lines, fn line ->
             if String.starts_with?(line, "JSON:") do
               payload = line |> String.trim_leading("JSON:") |> Jason.decode!()

               payload["method"] == "thread/fork" &&
                 get_in(payload, ["params", "path"]) == session_file &&
                 get_in(payload, ["params", "model"]) == "gpt-5.5" &&
                 get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                 get_in(payload, ["params", "sandbox"]) == "read-only"
             else
               false
             end
           end)
  end

  defp session_file(codex_home, session_id) do
    Path.join(codex_home, "sessions/2026/05/06/rollout-2026-05-06T00-00-00-#{session_id}.jsonl")
  end

  defp fake_observer_codex_script do
    """
    #!/bin/sh
    trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-observer.trace}"
    count=0

    while IFS= read -r line; do
      count=$((count + 1))
      printf 'JSON:%s\\n' "$line" >> "$trace_file"

      case "$count" in
        1)
          printf '%s\\n' '{"id":1,"result":{}}'
          ;;
        2)
          ;;
        3)
          printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-bootstrap"}}}'
          ;;
        4)
          printf '%s\\n' '{"id":4,"result":{"thread":{"id":"thread-forked"}}}'
          ;;
        5)
          printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-observer"}}}'
          printf '%s\\n' '{"method":"thread/tokenUsage/updated","params":{"threadId":"thread-forked","tokenUsage":{"total":{"inputTokens":1000,"cachedInputTokens":900,"outputTokens":50,"totalTokens":1050}}}}'
          printf '%s\\n' '{"method":"item/completed","params":{"threadId":"thread-forked","turnId":"turn-observer","item":{"id":"item-final","type":"agentMessage","phase":"final_answer","text":"observer final summary"}}}'
          printf '%s\\n' '{"method":"turn/completed"}'
          exit 0
          ;;
        *)
          exit 0
          ;;
      esac
    done
    """
  end

  defp session_events do
    [
      Jason.encode!(%{
        timestamp: "2026-05-05T15:00:00Z",
        type: "session_meta",
        payload: %{id: "session", cwd: "/tmp/source-workspace", model: "gpt-5.5", model_provider: "openai"}
      }),
      Jason.encode!(%{
        timestamp: "2026-05-05T15:00:01Z",
        type: "response_item",
        payload: %{type: "message", role: "user", content: [%{type: "input_text", text: "남은 작업 확인"}]}
      }),
      Jason.encode!(%{
        timestamp: "2026-05-05T15:00:02Z",
        type: "event_msg",
        payload: %{
          type: "token_count",
          info: %{
            last_token_usage: %{input_tokens: 1000, cached_input_tokens: 750, output_tokens: 50, total_tokens: 1050}
          }
        }
      })
    ]
  end

  defp old_external_summary(session_id, inspection_id, summary_text) do
    %{
      inspection_id: inspection_id,
      issue_id: "codex:#{session_id}",
      platform: "codex_cli_history",
      source_session: %{"id" => session_id},
      summary_text: summary_text,
      updated_at: "2026-05-05T15:00:00Z"
    }
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
