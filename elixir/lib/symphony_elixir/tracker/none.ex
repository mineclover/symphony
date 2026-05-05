defmodule SymphonyElixir.Tracker.None do
  @moduledoc """
  Tracker adapter for monitor-only deployments.
  """

  @behaviour SymphonyElixir.Tracker

  @spec fetch_candidate_issues() :: {:ok, []}
  def fetch_candidate_issues, do: {:ok, []}

  @spec fetch_issues_by_states([String.t()]) :: {:ok, []}
  def fetch_issues_by_states(_state_names), do: {:ok, []}

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, []}
  def fetch_issue_states_by_ids(_issue_ids), do: {:ok, []}

  @spec create_comment(String.t(), String.t()) :: {:ok, nil}
  def create_comment(_issue_id, _body), do: {:ok, nil}

  @spec update_issue_state(String.t(), String.t()) :: :ok
  def update_issue_state(_issue_id, _state_name), do: :ok
end
