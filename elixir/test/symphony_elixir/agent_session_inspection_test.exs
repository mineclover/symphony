defmodule SymphonyElixir.AgentSessionInspectionTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentSessionInspection

  defmodule FakeCachedCliAdapter do
    @behaviour AgentSessionInspection

    @impl true
    def platform, do: :fake_cached_cli

    @impl true
    def source_identity(%{id: id}), do: %{id: id}

    @impl true
    def observer_identity(%{id: id}), do: %{id: id}

    @impl true
    def clone_session(%{id: source_id}, _opts), do: {:ok, %{id: source_id <> "-observer"}}

    @impl true
    def run_observer_turn(%{id: observer_id}, prompt, _issue, _opts) do
      {:ok,
       %{
         id: observer_id <> "-turn",
         prompt: prompt,
         events: [%{event: :observer_completed}],
         summary_text: "outcome: inspected cached CLI session"
       }}
    end

    @impl true
    def summary_text(%{summary_text: summary_text}), do: summary_text

    @impl true
    def events(%{events: events}), do: events
  end

  test "summarize uses a platform adapter rather than Codex-specific assumptions" do
    issue = %{id: "issue-generic", identifier: "GEN-1"}
    source_session = %{id: "source-session"}

    assert {:ok, summary} =
             AgentSessionInspection.summarize(FakeCachedCliAdapter, source_session, issue)

    assert summary.platform == :fake_cached_cli
    assert summary.source_session == %{id: "source-session"}
    assert summary.observer_session == %{id: "source-session-observer"}
    assert summary.observer_turn.id == "source-session-observer-turn"
    assert summary.observer_turn.prompt =~ "cloned agent session"
    assert summary.summary_text == "outcome: inspected cached CLI session"
    assert summary.events == [%{event: :observer_completed}]
  end
end
