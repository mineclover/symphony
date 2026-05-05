defmodule SymphonyElixir.Codex.SessionInspectionAdapter do
  @moduledoc """
  Session-inspection adapter for Codex app-server threads.
  """

  @behaviour SymphonyElixir.AgentSessionInspection

  alias SymphonyElixir.Codex.AppServer

  @impl true
  def platform, do: :codex_app_server

  @impl true
  def source_identity(%{thread_id: thread_id}) do
    %{thread_id: thread_id}
  end

  @impl true
  def observer_identity(%{thread_id: thread_id}) do
    %{thread_id: thread_id}
  end

  @impl true
  def clone_session(app_session, opts) do
    AppServer.fork_session(app_session, observer_session_opts(opts))
  end

  defp observer_session_opts(opts) do
    opts
    |> Keyword.put_new(:approval_policy, "on-request")
    |> Keyword.put_new(:thread_sandbox, "read-only")
    |> Keyword.put_new(:turn_sandbox_policy, %{"type" => "readOnly", "networkAccess" => false})
  end

  @impl true
  def run_observer_turn(observer_session, prompt, issue, opts) do
    on_message = Keyword.get(opts, :on_message, fn _message -> :ok end)
    ref = make_ref()
    caller = self()

    collector = fn message ->
      send(caller, {ref, message})
      on_message.(message)
    end

    with {:ok, turn} <-
           AppServer.run_turn(observer_session, prompt, issue,
             on_message: collector,
             tool_executor: Keyword.get(opts, :tool_executor, &reject_observer_tool_call/2)
           ) do
      {:ok, Map.put(turn, :events, collect_events(ref, []))}
    end
  end

  @impl true
  def summary_text(%{events: events}) when is_list(events) do
    events
    |> Enum.flat_map(&agent_message_candidates/1)
    |> prefer_final_answer()
  end

  def summary_text(_observer_turn), do: nil

  @impl true
  def events(%{events: events}) when is_list(events), do: events
  def events(_observer_turn), do: []

  defp reject_observer_tool_call(tool, _arguments) do
    %{
      "success" => false,
      "output" => "Session inspector observer turns do not execute client-side tools: #{inspect(tool)}"
    }
  end

  defp collect_events(ref, acc) do
    receive do
      {^ref, message} when is_map(message) -> collect_events(ref, [message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp agent_message_candidates(%{payload: %{"method" => "item/completed", "params" => params}}) do
    case get_in(params, ["item"]) do
      %{"type" => "agentMessage", "text" => text} = item when is_binary(text) ->
        [{Map.get(item, "phase"), text}]

      %{"type" => "agent_message", "text" => text} = item when is_binary(text) ->
        [{Map.get(item, "phase"), text}]

      _ ->
        []
    end
  end

  defp agent_message_candidates(%{payload: %{"method" => "codex/event/agent_message", "params" => %{"msg" => msg}}}) do
    agent_message_from_msg(msg)
  end

  defp agent_message_candidates(%{
         payload: %{"method" => "codex/event/task_complete", "params" => %{"msg" => %{"last_agent_message" => text}}}
       })
       when is_binary(text) do
    [{"final_answer", text}]
  end

  defp agent_message_candidates(%{payload: %{"params" => %{"item" => item}}}) do
    case item do
      %{"type" => "agentMessage", "text" => text} = item when is_binary(text) ->
        [{Map.get(item, "phase"), text}]

      %{"type" => "agent_message", "text" => text} = item when is_binary(text) ->
        [{Map.get(item, "phase"), text}]

      %{"type" => type, "content" => content, "phase" => phase}
      when type in ["assistantMessage", "assistant_message", "agentMessage", "agent_message"] ->
        content
        |> content_text()
        |> maybe_agent_message(phase)

      _ ->
        []
    end
  end

  defp agent_message_candidates(_event), do: []

  defp agent_message_from_msg(%{"message" => text, "phase" => phase}) when is_binary(text), do: [{phase, text}]
  defp agent_message_from_msg(%{"text" => text, "phase" => phase}) when is_binary(text), do: [{phase, text}]
  defp agent_message_from_msg(%{"message" => text}) when is_binary(text), do: [{nil, text}]
  defp agent_message_from_msg(%{"text" => text}) when is_binary(text), do: [{nil, text}]
  defp agent_message_from_msg(_msg), do: []

  defp content_text(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"text" => text} when is_binary(text) -> text
      %{"type" => "output_text", "text" => text} when is_binary(text) -> text
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp content_text(_content), do: ""

  defp maybe_agent_message("", _phase), do: []
  defp maybe_agent_message(text, phase), do: [{phase, text}]

  defp prefer_final_answer(candidates) do
    candidates
    |> Enum.reverse()
    |> Enum.find_value(fn
      {"final_answer", text} -> String.trim(text)
      _candidate -> nil
    end) ||
      candidates
      |> List.last()
      |> candidate_text()
  end

  defp candidate_text({_phase, text}) when is_binary(text), do: String.trim(text)
  defp candidate_text(_candidate), do: nil
end
