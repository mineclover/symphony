defmodule SymphonyElixir.Codex.ExternalSessionAdapter do
  @moduledoc """
  External-session adapter for local Codex CLI history and rollout logs.
  """

  @behaviour SymphonyElixir.ExternalSessionAdapter

  alias SymphonyElixir.AgentSessionInspection
  alias SymphonyElixir.Codex.{AppServer, SessionInspectionAdapter, SessionLog}
  alias SymphonyElixir.Config
  alias SymphonyElixir.ExternalSessionAdapter
  alias SymphonyElixir.Linear.Issue

  @impl true
  @spec platform() :: atom()
  def platform, do: :codex_cli_history

  @impl true
  @spec enabled?() :: boolean()
  def enabled? do
    settings = Config.settings!()
    settings.tracker.kind == "none" and settings.session_inspection.enabled == true
  rescue
    _error -> false
  end

  @impl true
  @spec initial_cursor() :: non_neg_integer()
  def initial_cursor, do: SessionLog.history_file_size()

  @impl true
  @spec read_events(non_neg_integer()) :: {non_neg_integer(), [SessionLog.history_entry()]}
  def read_events(cursor), do: SessionLog.read_history_entries(cursor)

  @impl true
  @spec source_session(SessionLog.history_entry()) :: {:ok, SessionLog.source_session()} | {:error, term()}
  def source_session(event), do: SessionLog.source_session(event)

  @impl true
  @spec source_identity(SessionLog.source_session()) :: map()
  def source_identity(source_session) do
    %{
      id: source_session.id,
      path: source_session.path,
      status: source_session.status,
      mtime: source_session.mtime,
      cwd: source_session.cwd,
      model: source_session.model,
      model_provider: source_session.model_provider
    }
  end

  @impl true
  @spec issue_id(SessionLog.source_session()) :: String.t()
  def issue_id(source_session), do: "codex:#{source_session.id}"

  @impl true
  @spec issue_identifier(SessionLog.source_session()) :: String.t()
  def issue_identifier(source_session), do: "CODEX-#{String.slice(source_session.id, 0, 8)}"

  @impl true
  @spec inspection_id(SessionLog.source_session()) :: String.t()
  def inspection_id(source_session), do: "codex:#{source_session.id}:latest"

  @impl true
  @spec cache_analysis(SessionLog.source_session()) :: map()
  def cache_analysis(source_session), do: source_session.cache_analysis

  @impl true
  @spec latest_user_query(SessionLog.source_session()) :: String.t()
  def latest_user_query(source_session), do: source_session.latest_user_query

  @impl true
  @spec status(SessionLog.source_session()) :: String.t()
  def status(source_session), do: source_session.status

  @impl true
  @spec observer_summary(SessionLog.source_session(), keyword()) ::
          {:ok, ExternalSessionAdapter.observer_summary()} | {:error, term()}
  def observer_summary(source_session, _opts) do
    workspace = observer_workspace()
    issue = %Issue{id: issue_id(source_session), identifier: issue_identifier(source_session), title: "External Codex session"}

    ref = make_ref()
    caller = self()

    collector = fn message ->
      send(caller, {ref, message})
      :ok
    end

    case AppServer.start_session(workspace, observer_start_opts()) do
      {:ok, session} ->
        try do
          with {:ok, observer_session} <- AppServer.fork_session(session, observer_fork_opts(source_session)) do
            case AppServer.run_turn(observer_session, SessionLog.observer_prompt(source_session), issue,
                   tool_executor: &reject_tool_call/2,
                   on_message: collector
                 ) do
              {:ok, turn} ->
                events = collect_events(ref, [])
                turn = Map.put(turn, :events, events)

                {:ok,
                 %{
                   observer_session: observer_identity(observer_session, source_session),
                   observer_turn: %{
                     session_id: Map.get(turn, :session_id),
                     thread_id: Map.get(turn, :thread_id),
                     turn_id: Map.get(turn, :turn_id)
                   },
                   summary_text: SessionInspectionAdapter.summary_text(turn),
                   observer_cache_analysis: AgentSessionInspection.cache_analysis(events),
                   events: events
                 }}

              {:error, reason} ->
                events = collect_events(ref, [])

                {:ok,
                 %{
                   observer_session: observer_identity(observer_session, source_session),
                   observer_turn: nil,
                   summary_text: "Observer summary failed: #{inspect(reason)}",
                   error: inspect(reason),
                   observer_cache_analysis: AgentSessionInspection.cache_analysis(events),
                   events: events
                 }}
            end
          else
            {:error, reason} -> {:error, reason}
          end
        after
          AppServer.stop_session(session)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reject_tool_call(tool, _arguments) do
    %{
      "success" => false,
      "output" => "External session observers do not execute tools: #{inspect(tool)}"
    }
  end

  defp collect_events(ref, acc) do
    receive do
      {^ref, message} when is_map(message) -> collect_events(ref, [message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp observer_identity(observer_session, source_session) do
    %{
      thread_id: Map.get(observer_session, :thread_id),
      source_path: source_session.path,
      clone_strategy: :codex_thread_fork_path
    }
  end

  defp observer_fork_opts(source_session) do
    [
      path: source_session.path,
      model: source_session.model,
      model_provider: source_session.model_provider,
      approval_policy: "on-request",
      thread_sandbox: "read-only",
      turn_sandbox_policy: %{"type" => "readOnly", "networkAccess" => false},
      ephemeral: true,
      persist_extended_history: true
    ]
  end

  defp observer_start_opts do
    [
      approval_policy: "on-request",
      thread_sandbox: "read-only",
      turn_sandbox_policy: %{"type" => "readOnly", "networkAccess" => false}
    ]
  end

  defp observer_workspace do
    workspace =
      Config.settings!().workspace.root
      |> Path.join(".symphony-observer")
      |> Path.expand()

    File.mkdir_p!(workspace)
    workspace
  end
end
