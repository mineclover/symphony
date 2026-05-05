defmodule SymphonyElixir.Codex.ExternalSessionMonitor do
  @moduledoc """
  Compatibility wrapper for the Codex external-session monitor.
  """

  alias SymphonyElixir.Codex.ExternalSessionAdapter
  alias SymphonyElixir.ExternalSessionMonitor

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts
    |> Keyword.put_new(:adapter, ExternalSessionAdapter)
    |> ExternalSessionMonitor.child_spec()
  end

  @spec start_link(keyword()) :: GenServer.on_start() | :ignore
  def start_link(opts \\ []) do
    opts
    |> Keyword.put_new(:adapter, ExternalSessionAdapter)
    |> ExternalSessionMonitor.start_link()
  end
end
