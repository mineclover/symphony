defmodule SymphonyElixir.ExternalSessionAdapter do
  @moduledoc """
  Behaviour for external agent session monitors.

  Implementations watch an agent-specific session source, resolve changed
  sessions into a normalized source-session map, and run a read-only observer
  summary against a cloned or resumed cached session.
  """

  @type cursor :: term()
  @type event :: map()
  @type source_session :: map()
  @type observer_summary :: map()

  @callback platform() :: atom()
  @callback enabled?() :: boolean()
  @callback initial_cursor() :: cursor()
  @callback read_events(cursor()) :: {cursor(), [event()]}
  @callback source_session(event()) :: {:ok, source_session()} | {:error, term()}
  @callback source_identity(source_session()) :: map()
  @callback issue_id(source_session()) :: String.t()
  @callback issue_identifier(source_session()) :: String.t()
  @callback inspection_id(source_session()) :: String.t()
  @callback cache_analysis(source_session()) :: map() | nil
  @callback latest_user_query(source_session()) :: String.t() | nil
  @callback status(source_session()) :: String.t() | nil
  @callback observer_summary(source_session(), keyword()) :: {:ok, observer_summary()} | {:error, term()}

  @optional_callbacks enabled?: 0
end
