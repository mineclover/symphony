defmodule SymphonyElixir.AgentSessionInspection do
  @moduledoc """
  Generic inspection flow for agent CLIs that can resume, fork, or otherwise
  clone a cached session without mutating the source session.
  """

  @default_summary_prompt """
  You are observing a completed Symphony worker session from a cloned agent session.

  Summarize the session for an operator who needs to understand it without reading the full transcript.
  Do not continue or modify the original task. Do not ask follow-up questions.

  Return:
  - outcome: what changed or what was decided
  - work_units: distinct tasks handled in this session
  - important_context: constraints, blockers, approvals, or notable events
  - verification: checks/tests run and their result
  - next_steps: concrete remaining work, if any
  """

  @type session :: map()
  @type observer_turn :: map()
  @type summary :: %{
          platform: atom(),
          source_session: map(),
          observer_session: map(),
          observer_turn: map(),
          summary_text: String.t() | nil,
          events: [map()]
        }

  @callback platform() :: atom()
  @callback source_identity(session()) :: map()
  @callback observer_identity(session()) :: map()
  @callback clone_session(session(), keyword()) :: {:ok, session()} | {:error, term()}
  @callback run_observer_turn(session(), String.t(), map(), keyword()) ::
              {:ok, observer_turn()} | {:error, term()}
  @callback summary_text(observer_turn()) :: String.t() | nil
  @callback events(observer_turn()) :: [map()]

  @spec summarize(module(), session(), map(), keyword()) :: {:ok, summary()} | {:error, term()}
  def summarize(adapter, source_session, issue, opts \\ [])
      when is_atom(adapter) and is_map(source_session) and is_map(issue) do
    prompt = Keyword.get(opts, :prompt, @default_summary_prompt)

    with {:ok, observer_session} <- adapter.clone_session(source_session, opts),
         {:ok, observer_turn} <- adapter.run_observer_turn(observer_session, prompt, issue, opts) do
      {:ok,
       %{
         platform: adapter.platform(),
         source_session: adapter.source_identity(source_session),
         observer_session: adapter.observer_identity(observer_session),
         observer_turn: observer_turn,
         summary_text: adapter.summary_text(observer_turn),
         events: adapter.events(observer_turn)
       }}
    end
  end
end
