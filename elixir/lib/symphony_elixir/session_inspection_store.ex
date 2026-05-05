defmodule SymphonyElixir.SessionInspectionStore do
  @moduledoc """
  File-backed history store for observer session summaries.
  """

  alias SymphonyElixir.Config

  @type summary :: map()
  @type history :: %{optional(String.t()) => [summary()]}

  @default_relative_path ".symphony/session_inspections.jsonl"

  @spec load() :: history()
  def load do
    storage_file()
    |> read_lines()
    |> Enum.reduce(%{}, fn line, histories ->
      case Jason.decode(line) do
        {:ok, %{} = summary} ->
          issue_id = Map.get(summary, "issue_id")

          if is_binary(issue_id) do
            Map.update(histories, issue_id, [summary], &put_summary(List.wrap(&1), summary))
          else
            histories
          end

        _ ->
          histories
      end
    end)
    |> Map.new(fn {issue_id, summaries} -> {issue_id, Enum.reverse(summaries)} end)
  end

  @spec append(summary()) :: {:ok, summary()} | {:error, term()}
  def append(summary) when is_map(summary) do
    normalized =
      summary
      |> put_default(:inspection_id, inspection_id(summary))
      |> normalize()

    file = storage_file()

    with :ok <- File.mkdir_p(Path.dirname(file)),
         {:ok, encoded} <- encode_upserted_lines(file, normalized),
         :ok <- File.write(file, encoded) do
      {:ok, normalized}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec storage_file() :: Path.t()
  def storage_file do
    Application.get_env(:symphony_elixir, :session_inspection_store_file) ||
      Path.join(Config.settings!().workspace.root, @default_relative_path)
  end

  defp read_lines(file) do
    case File.read(file) do
      {:ok, contents} -> String.split(contents, "\n", trim: true)
      {:error, :enoent} -> []
      {:error, _reason} -> []
    end
  end

  defp encode_upserted_lines(file, normalized) do
    storage_key = storage_key(normalized)

    summaries =
      file
      |> read_lines()
      |> Enum.flat_map(&decode_summary/1)
      |> Enum.reject(&(storage_key(&1) == storage_key))
      |> Kernel.++([normalized])

    case Jason.encode(summaries) do
      {:ok, _encoded_list} ->
        encoded_lines =
          summaries
          |> Enum.map(&Jason.encode!/1)
          |> Enum.join("\n")

        {:ok, encoded_lines <> "\n"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_summary(line) do
    case Jason.decode(line) do
      {:ok, %{} = summary} -> [summary]
      _ -> []
    end
  end

  defp put_summary(history, summary) do
    key = storage_key(summary)
    [summary | Enum.reject(history, &(storage_key(&1) == key))]
  end

  defp storage_key(summary) do
    case {map_get(summary, :platform), map_get(map_get(summary, :source_session) || %{}, :id)} do
      {platform, source_session_id} when not is_nil(platform) and is_binary(source_session_id) ->
        "external-session:#{platform}:#{source_session_id}"

      _ ->
        map_get(summary, :inspection_id) || Map.fetch!(summary, "inspection_id")
    end
  end

  defp put_default(summary, key, value) do
    Map.put_new(summary, key, value)
  end

  defp inspection_id(summary) do
    [
      map_get(summary, :issue_id) || "issue",
      map_get(summary, :source_turn_number) || "turn",
      get_in(map_get(summary, :observer_turn) || %{}, [:turn_id]) ||
        get_in(map_get(summary, :observer_turn) || %{}, ["turn_id"]) ||
        System.unique_integer([:positive])
    ]
    |> Enum.map(&to_string/1)
    |> Enum.join(":")
  end

  defp normalize(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp normalize(%{} = map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), normalize(value)} end)
  end

  defp normalize(values) when is_list(values), do: Enum.map(values, &normalize/1)
  defp normalize(nil), do: nil
  defp normalize(true), do: true
  defp normalize(false), do: false
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value) when is_tuple(value), do: inspect(value)
  defp normalize(value) when is_pid(value), do: inspect(value)
  defp normalize(value) when is_reference(value), do: inspect(value)
  defp normalize(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)

  defp map_get(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
