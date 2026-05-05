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
          observer: true,
          source_session: map(),
          observer_session: map(),
          observer_turn: map(),
          summary_text: String.t() | nil,
          cache_analysis: map(),
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
         observer: true,
         source_session: adapter.source_identity(source_session),
         observer_session: adapter.observer_identity(observer_session),
         observer_turn: observer_turn,
         summary_text: adapter.summary_text(observer_turn),
         cache_analysis: cache_analysis(adapter.events(observer_turn)),
         events: adapter.events(observer_turn)
       }}
    end
  end

  @spec comment_body(summary()) :: String.t()
  def comment_body(%{
        platform: platform,
        source_session: source_session,
        observer_session: observer_session,
        summary_text: summary_text,
        cache_analysis: cache_analysis
      }) do
    [
      "Symphony session summary",
      "",
      "Platform: #{platform}",
      "Source session: #{format_identity(source_session)}",
      "Observer session: #{format_identity(observer_session)}",
      "Cache: #{format_cache_analysis(cache_analysis)}",
      "",
      String.trim(to_string(summary_text || ""))
    ]
    |> Enum.join("\n")
    |> String.trim()
  end

  @spec create_comment(summary(), String.t(), keyword()) :: {:ok, String.t() | nil} | {:error, term()}
  def create_comment(summary, issue_id, opts \\ []) when is_map(summary) and is_binary(issue_id) do
    tracker = Keyword.get(opts, :tracker, SymphonyElixir.Tracker)

    case tracker.create_comment(issue_id, comment_body(summary)) do
      :ok -> {:ok, nil}
      {:ok, comment_id} -> {:ok, comment_id}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_comment_result, other}}
    end
  end

  @spec cache_analysis([map()]) :: map()
  def cache_analysis(events) when is_list(events) do
    samples =
      events
      |> Enum.flat_map(&usage_samples/1)
      |> Enum.filter(fn sample ->
        sample.input_tokens || sample.cached_input_tokens || sample.total_tokens
      end)

    cached_input_tokens =
      samples
      |> Enum.map(&(&1.cached_input_tokens || 0))
      |> Enum.max(fn -> 0 end)

    input_tokens =
      samples
      |> Enum.map(&(&1.input_tokens || 0))
      |> Enum.max(fn -> 0 end)

    %{
      cache_hit?: cached_input_tokens > 0,
      cached_input_tokens: cached_input_tokens,
      input_tokens: input_tokens,
      cache_hit_ratio: cache_hit_ratio(cached_input_tokens, input_tokens),
      samples: samples
    }
  end

  defp usage_samples(value) when is_map(value) do
    sample =
      %{
        input_tokens: integer_at(value, ["input_tokens", :input_tokens, "inputTokens", :inputTokens]),
        cached_input_tokens:
          integer_at(value, [
            "cached_input_tokens",
            :cached_input_tokens,
            "cachedInputTokens",
            :cachedInputTokens
          ]),
        output_tokens: integer_at(value, ["output_tokens", :output_tokens, "outputTokens", :outputTokens]),
        total_tokens: integer_at(value, ["total_tokens", :total_tokens, "totalTokens", :totalTokens])
      }

    nested =
      value
      |> Map.values()
      |> Enum.flat_map(&usage_samples/1)

    if sample.input_tokens || sample.cached_input_tokens || sample.output_tokens || sample.total_tokens do
      [sample | nested]
    else
      nested
    end
  end

  defp usage_samples(values) when is_list(values), do: Enum.flat_map(values, &usage_samples/1)
  defp usage_samples(_value), do: []

  defp integer_at(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        value when is_integer(value) -> value
        _ -> nil
      end
    end)
  end

  defp cache_hit_ratio(_cached_input_tokens, input_tokens) when not is_integer(input_tokens) or input_tokens <= 0,
    do: nil

  defp cache_hit_ratio(cached_input_tokens, input_tokens) when is_integer(cached_input_tokens) do
    cached_input_tokens / input_tokens
  end

  defp format_identity(identity) when is_map(identity) do
    identity
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp format_cache_analysis(%{cache_hit?: true, cached_input_tokens: cached, input_tokens: input}) do
    ratio = cache_hit_ratio(cached, input)

    if is_float(ratio) do
      "hit cached_input_tokens=#{cached} input_tokens=#{input} ratio=#{Float.round(ratio, 4)}"
    else
      "hit cached_input_tokens=#{cached}"
    end
  end

  defp format_cache_analysis(%{cache_hit?: false}), do: "miss"
end
