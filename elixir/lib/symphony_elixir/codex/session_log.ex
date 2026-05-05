defmodule SymphonyElixir.Codex.SessionLog do
  @moduledoc """
  Reads local Codex CLI history and rollout JSONL files for monitor-only inspection.
  """

  @type history_entry :: %{
          session_id: String.t(),
          latest_user_query: String.t(),
          ts: integer() | nil
        }

  @type source_session :: %{
          id: String.t(),
          status: String.t(),
          mtime: DateTime.t() | nil,
          path: Path.t() | nil,
          cwd: Path.t() | nil,
          model: String.t() | nil,
          model_provider: String.t() | nil,
          latest_user_query: String.t(),
          cache_analysis: map(),
          transcript_excerpt: String.t()
        }

  @observer_marker "SYMPHONY_EXTERNAL_SESSION_OBSERVER"

  @spec observer_marker() :: String.t()
  def observer_marker, do: @observer_marker

  @spec history_file() :: Path.t()
  def history_file do
    Application.get_env(:symphony_elixir, :codex_history_file) ||
      Path.join(codex_home(), "history.jsonl")
  end

  @spec history_file_size() :: non_neg_integer()
  def history_file_size do
    case File.stat(history_file()) do
      {:ok, %File.Stat{size: size}} when is_integer(size) and size >= 0 -> size
      _ -> 0
    end
  end

  @spec read_history_entries(non_neg_integer()) :: {non_neg_integer(), [history_entry()]}
  def read_history_entries(offset) when is_integer(offset) and offset >= 0 do
    file = history_file()

    case File.read(file) do
      {:ok, contents} ->
        size = byte_size(contents)
        offset = min(offset, size)

        entries =
          contents
          |> binary_part(offset, size - offset)
          |> String.split("\n", trim: true)
          |> Enum.flat_map(&decode_history_entry/1)

        {size, entries}

      {:error, _reason} ->
        {0, []}
    end
  end

  @spec source_session(history_entry()) :: {:ok, source_session()} | {:error, term()}
  def source_session(%{session_id: session_id, latest_user_query: latest_user_query}) do
    with {:ok, path} <- session_file(session_id) do
      events = decode_jsonl(path)
      stat = File.stat(path)

      {:ok,
       %{
         id: session_id,
         status: status(stat),
         mtime: mtime(stat),
         path: path,
         cwd: session_cwd(events),
         model: session_model(events),
         model_provider: session_model_provider(events),
         latest_user_query: latest_user_query,
         cache_analysis: cache_analysis(events),
         transcript_excerpt: transcript_excerpt(events, latest_user_query)
       }}
    end
  end

  @spec session_file(String.t()) :: {:ok, Path.t()} | {:error, :session_file_not_found}
  def session_file(session_id) when is_binary(session_id) do
    codex_home()
    |> Path.join("sessions/*/*/*/rollout-*#{session_id}.jsonl")
    |> Path.wildcard()
    |> Enum.max_by(&mtime_unix/1, fn -> nil end)
    |> case do
      path when is_binary(path) -> {:ok, path}
      nil -> {:error, :session_file_not_found}
    end
  end

  @spec observer_prompt(source_session()) :: String.t()
  def observer_prompt(source_session) when is_map(source_session) do
    """
    #{@observer_marker}

    You are observing a Codex CLI session from a read-only exported transcript summary.
    Do not continue the source task. Do not modify files. Do not use tools.

    Return:
    - status: what the source session appears to be doing
    - latest_user_query: what the operator asked most recently
    - work_units: distinct work items visible from the excerpt
    - cache: whether cached input tokens are visible and the reported ratio
    - next_observer_note: what an operator should know next

    Source session id: #{source_session.id}
    Source status: #{source_session.status}
    Source mtime: #{format_datetime(source_session.mtime)}
    Source cwd: #{source_session.cwd || "n/a"}
    Source model: #{source_session.model || "unknown"}
    Source model provider: #{source_session.model_provider || "unknown"}
    Latest user query:
    #{source_session.latest_user_query}

    Cache analysis:
    #{inspect(source_session.cache_analysis, pretty: true, limit: :infinity)}

    Transcript excerpt:
    #{source_session.transcript_excerpt}
    """
    |> String.trim()
  end

  defp decode_history_entry(line) do
    with {:ok, %{"session_id" => session_id, "text" => text} = payload} <- Jason.decode(line),
         true <- is_binary(session_id),
         true <- is_binary(text),
         false <- String.contains?(text, @observer_marker) do
      [%{session_id: session_id, latest_user_query: text, ts: Map.get(payload, "ts")}]
    else
      _ -> []
    end
  end

  defp decode_jsonl(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, event} -> [event]
        _ -> []
      end
    end)
  rescue
    _error -> []
  end

  defp session_cwd(events) do
    session_meta_value(events, "cwd")
  end

  defp session_meta_value(events, key) when is_binary(key) do
    Enum.find_value(events, fn
      %{"type" => "session_meta", "payload" => payload} when is_map(payload) ->
        case Map.get(payload, key) do
          value when is_binary(value) and value != "" -> value
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp session_model(events) do
    session_meta_value(events, "model") || turn_context_value(events, "model")
  end

  defp session_model_provider(events) do
    session_meta_value(events, "model_provider") || session_meta_value(events, "modelProvider") ||
      turn_context_value(events, "model_provider") || turn_context_value(events, "modelProvider")
  end

  defp turn_context_value(events, key) when is_binary(key) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "turn_context", "payload" => payload} when is_map(payload) ->
        case Map.get(payload, key) do
          value when is_binary(value) and value != "" -> value
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp cache_analysis(events) do
    usage =
      events
      |> Enum.reverse()
      |> Enum.find_value(&usage_from_event/1)

    input_tokens = integer_at(usage || %{}, ["input_tokens", "inputTokens"])
    cached_input_tokens = integer_at(usage || %{}, ["cached_input_tokens", "cachedInputTokens"])

    %{
      cache_hit?: is_integer(cached_input_tokens) and cached_input_tokens > 0,
      cached_input_tokens: cached_input_tokens || 0,
      input_tokens: input_tokens || 0,
      cache_hit_ratio: cache_hit_ratio(cached_input_tokens || 0, input_tokens || 0)
    }
  end

  defp usage_from_event(%{"type" => "event_msg", "payload" => %{"type" => "token_count", "info" => info}}) do
    Map.get(info, "last_token_usage") || Map.get(info, "total_token_usage")
  end

  defp usage_from_event(%{"payload" => %{"info" => info}}) when is_map(info) do
    Map.get(info, "last_token_usage") || Map.get(info, "total_token_usage")
  end

  defp usage_from_event(_event), do: nil

  defp transcript_excerpt(events, latest_user_query) do
    tail =
      events
      |> Enum.take(-80)
      |> Enum.flat_map(&event_excerpt/1)
      |> Enum.take(-20)

    ["latest_user_query: #{latest_user_query}" | tail]
    |> Enum.join("\n")
    |> String.slice(0, 12_000)
  end

  defp event_excerpt(%{"type" => "response_item", "payload" => %{"type" => "message", "role" => role, "content" => content}}) do
    text = content_text(content)
    if text == "", do: [], else: ["#{role}: #{text}"]
  end

  defp event_excerpt(%{"type" => "event_msg", "payload" => %{"type" => type}}), do: ["event: #{type}"]
  defp event_excerpt(%{"type" => type}), do: ["event: #{type}"]
  defp event_excerpt(_event), do: []

  defp content_text(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"text" => text} when is_binary(text) -> text
      %{"type" => "input_text", "text" => text} when is_binary(text) -> text
      %{"type" => "output_text", "text" => text} when is_binary(text) -> text
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 1_500)
  end

  defp content_text(_content), do: ""

  defp status({:ok, %File.Stat{} = stat}) do
    age_seconds = System.os_time(:second) - mtime_unix(stat)
    if age_seconds <= 30, do: "active_recently", else: "idle"
  end

  defp status(_stat), do: "unknown"

  defp mtime({:ok, %File.Stat{mtime: mtime}}), do: mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
  defp mtime(_stat), do: nil

  defp mtime_unix(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, stat} -> mtime_unix(stat)
      _ -> 0
    end
  end

  defp mtime_unix(%File.Stat{mtime: mtime}) do
    mtime
    |> NaiveDateTime.from_erl!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end

  defp integer_at(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        value when is_integer(value) -> value
        _ -> nil
      end
    end)
  end

  defp cache_hit_ratio(_cached_input_tokens, input_tokens) when input_tokens <= 0, do: nil
  defp cache_hit_ratio(cached_input_tokens, input_tokens), do: cached_input_tokens / input_tokens

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(_datetime), do: "n/a"

  defp codex_home do
    Application.get_env(:symphony_elixir, :codex_home) ||
      Path.join(System.user_home!(), ".codex")
  end
end
