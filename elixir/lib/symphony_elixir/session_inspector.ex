defmodule SymphonyElixir.SessionInspector do
  @moduledoc """
  Backwards-compatible Codex app-server entry point for session inspection.

  New session-inspection integrations should use `SymphonyElixir.AgentSessionInspection`
  with a platform-specific adapter.
  """

  alias SymphonyElixir.AgentSessionInspection
  alias SymphonyElixir.Codex.SessionInspectionAdapter

  @type summary :: %{
          source_thread_id: String.t(),
          observer_thread_id: String.t(),
          observer_session_id: String.t(),
          summary_text: String.t() | nil,
          events: [map()]
        }

  @spec summarize(SymphonyElixir.Codex.AppServer.session(), map(), keyword()) ::
          {:ok, summary()} | {:error, term()}
  def summarize(app_session, issue, opts \\ []) when is_map(app_session) and is_map(issue) do
    with {:ok, inspection} <- AgentSessionInspection.summarize(SessionInspectionAdapter, app_session, issue, opts) do
      {:ok,
       %{
         source_thread_id: inspection.source_session.thread_id,
         observer_thread_id: inspection.observer_session.thread_id,
         observer_session_id: inspection.observer_turn.session_id,
         summary_text: inspection.summary_text,
         events: inspection.events
       }}
    end
  end
end
