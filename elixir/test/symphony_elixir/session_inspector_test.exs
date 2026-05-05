defmodule SymphonyElixir.SessionInspectorTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.SessionInspector

  test "summarize forks a live app-server thread and returns the observer final answer" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-session-inspector-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-INSPECT")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-inspector.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

      on_exit(fn ->
        restore_env("SYMP_TEST_CODEx_TRACE", previous_trace)
      end)

      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-inspector.trace}"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-source"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-source"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
          5)
            printf '%s\\n' '{"id":4,"result":{"thread":{"id":"thread-observer"}}}'
            ;;
          6)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-observer"}}}'
            printf '%s\\n' '{"method":"item/completed","params":{"threadId":"thread-observer","turnId":"turn-observer","item":{"id":"item-summary","type":"agentMessage","phase":"final_answer","text":"outcome: changed tests\\nwork_units: one implementation task"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server"
      )

      issue = %Issue{
        id: "issue-inspect",
        identifier: "MT-INSPECT",
        title: "Inspect session",
        description: "Validate session inspector",
        state: "In Progress",
        url: "https://example.org/issues/MT-INSPECT",
        labels: ["backend"]
      }

      {:ok, session} = AppServer.start_session(workspace)

      try do
        assert {:ok, %{session_id: "thread-source-turn-source"}} =
                 AppServer.run_turn(session, "Do source work", issue)

        assert {:ok, summary} = SessionInspector.summarize(session, issue)

        assert summary.source_thread_id == "thread-source"
        assert summary.observer_thread_id == "thread-observer"
        assert summary.observer_session_id == "thread-observer-turn-observer"
        assert summary.summary_text =~ "outcome: changed tests"
        assert Enum.any?(summary.events, &(&1.event == :turn_completed))

        trace = File.read!(trace_file)
        lines = String.split(trace, "\n", trim: true)

        assert Enum.any?(lines, fn line ->
                 if String.starts_with?(line, "JSON:") do
                   payload = line |> String.trim_leading("JSON:") |> Jason.decode!()

                   payload["method"] == "thread/fork" &&
                     get_in(payload, ["params", "threadId"]) == "thread-source" &&
                     get_in(payload, ["params", "ephemeral"]) == true
                 else
                   false
                 end
               end)

        observer_turn =
          Enum.find(lines, fn line ->
            if String.starts_with?(line, "JSON:") do
              payload = line |> String.trim_leading("JSON:") |> Jason.decode!()
              payload["method"] == "turn/start" && get_in(payload, ["params", "threadId"]) == "thread-observer"
            else
              false
            end
          end)

        assert is_binary(observer_turn)
      after
        AppServer.stop_session(session)
      end
    after
      File.rm_rf(test_root)
    end
  end
end
