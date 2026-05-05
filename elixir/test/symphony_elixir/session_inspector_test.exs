defmodule SymphonyElixir.SessionInspectorTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentSessionInspection
  alias SymphonyElixir.Codex.SessionInspectionAdapter

  test "summary_text accepts codex event agent messages and task completion fallback" do
    assert SessionInspectionAdapter.summary_text(%{
             events: [
               %{
                 payload: %{
                   "method" => "codex/event/agent_message",
                   "params" => %{"msg" => %{"type" => "agent_message", "message" => "commentary", "phase" => "commentary"}}
                 }
               },
               %{
                 payload: %{
                   "method" => "codex/event/agent_message",
                   "params" => %{
                     "msg" => %{"type" => "agent_message", "message" => "final observer answer", "phase" => "final_answer"}
                   }
                 }
               }
             ]
           }) == "final observer answer"

    assert SessionInspectionAdapter.summary_text(%{
             events: [
               %{
                 payload: %{
                   "method" => "codex/event/task_complete",
                   "params" => %{"msg" => %{"last_agent_message" => "last agent message"}}
                 }
               }
             ]
           }) == "last agent message"
  end

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
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-source"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-source"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
          5)
            printf '%s\\n' '{"id":4,"result":{"thread":{"id":"thread-observer"}}}'
            ;;
          6)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-observer"}}}'
            printf '%s\\n' '{"method":"item/completed","params":{"threadId":"thread-observer","turnId":"turn-observer","item":{"id":"item-commentary","type":"agentMessage","phase":"commentary","text":"intermediate observer note"}}}'
            printf '%s\\n' '{"method":"thread/tokenUsage/updated","params":{"threadId":"thread-observer","tokenUsage":{"total":{"inputTokens":1000,"cachedInputTokens":750,"outputTokens":80,"totalTokens":1080}}}}'
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
        tracker_kind: "memory",
        codex_command: "#{codex_binary} app-server"
      )

      Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

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

        assert {:ok, summary} =
                 AgentSessionInspection.summarize(SessionInspectionAdapter, session, issue)

        assert summary.observer == true
        assert summary.platform == :codex_app_server
        assert summary.source_session == %{thread_id: "thread-source"}
        assert summary.observer_session == %{thread_id: "thread-observer"}
        assert summary.observer_turn.session_id == "thread-observer-turn-observer"
        assert summary.summary_text =~ "outcome: changed tests"
        refute summary.summary_text =~ "intermediate observer note"
        assert Enum.any?(summary.events, &(&1.event == :turn_completed))
        assert Enum.any?(summary.events, &(&1.session_id == "thread-observer-turn-observer"))

        assert Map.fetch!(summary.cache_analysis, :cache_hit?) == true
        assert summary.cache_analysis.cached_input_tokens == 750
        assert summary.cache_analysis.input_tokens == 1000
        assert summary.cache_analysis.cache_hit_ratio == 0.75

        comment_body = AgentSessionInspection.comment_body(summary)
        assert comment_body =~ "Symphony session summary"
        assert comment_body =~ "Source session: thread_id=thread-source"
        assert comment_body =~ "Observer session: thread_id=thread-observer"
        assert comment_body =~ "Cache: hit cached_input_tokens=750 input_tokens=1000 ratio=0.75"
        assert comment_body =~ "outcome: changed tests"
        refute comment_body =~ "intermediate observer note"

        assert {:ok, comment_id} = AgentSessionInspection.create_comment(summary, issue.id)
        assert_receive {:memory_tracker_comment, "issue-inspect", ^comment_body, ^comment_id}

        trace = File.read!(trace_file)
        lines = String.split(trace, "\n", trim: true)

        assert Enum.any?(lines, fn line ->
                 if String.starts_with?(line, "JSON:") do
                   payload = line |> String.trim_leading("JSON:") |> Jason.decode!()

                   payload["method"] == "thread/fork" &&
                     get_in(payload, ["params", "threadId"]) == "thread-source" &&
                     get_in(payload, ["params", "ephemeral"]) == true &&
                     get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                     get_in(payload, ["params", "sandbox"]) == "read-only"
                 else
                   false
                 end
               end)

        observer_turn =
          Enum.find(lines, fn line ->
            if String.starts_with?(line, "JSON:") do
              payload = line |> String.trim_leading("JSON:") |> Jason.decode!()

              payload["method"] == "turn/start" &&
                get_in(payload, ["params", "threadId"]) == "thread-observer" &&
                get_in(payload, ["params", "approvalPolicy"]) == "on-request" &&
                get_in(payload, ["params", "sandboxPolicy"]) == %{
                  "type" => "readOnly",
                  "networkAccess" => false
                }
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
