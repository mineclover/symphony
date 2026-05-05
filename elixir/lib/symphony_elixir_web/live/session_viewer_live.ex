defmodule SymphonyElixirWeb.SessionViewerLive do
  @moduledoc """
  Live session observer surface for cloned external-session summaries.
  """

  use Phoenix.LiveView, layout: {SymphonyElixirWeb.Layouts, :app}

  alias SymphonyElixirWeb.{Endpoint, ObservabilityPubSub, Presenter}

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :payload, load_payload())

    if connected?(socket) do
      :ok = ObservabilityPubSub.subscribe()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:observability_updated, socket) do
    {:noreply, assign(socket, :payload, load_payload())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="session-viewer-shell ds-shell">
      <header class="session-viewer-hero ds-panel ds-panel-hero">
        <div>
          <p class="eyebrow ds-kicker">Session Observer</p>
          <h1 class="session-viewer-title">Session summaries</h1>
          <p class="session-viewer-copy">
            Cloned worker sessions summarized by observer turns, with source and observer cache visibility.
          </p>
        </div>

        <nav class="session-viewer-actions" aria-label="Session viewer navigation">
          <a class="ds-tab session-viewer-action" href="/">Runtime dashboard</a>
          <a class="ds-tab session-viewer-action" href="#session-summary-list">Summaries</a>
        </nav>
      </header>

      <%= if @payload[:error] do %>
        <section class="error-card ds-panel">
          <h2 class="error-title">Snapshot unavailable</h2>
          <p class="error-copy">
            <strong><%= @payload.error.code %>:</strong> <%= @payload.error.message %>
          </p>
        </section>
      <% else %>
        <section class="session-viewer-stats">
          <article class="metric-card ds-panel">
            <p class="metric-label">Summaries</p>
            <p class="metric-value numeric"><%= length(@payload.session_inspections) %></p>
            <p class="metric-detail">Observer records available for review.</p>
          </article>

          <article class="metric-card ds-panel">
            <p class="metric-label">Cache hits</p>
            <p class="metric-value numeric"><%= cache_hit_count(@payload.session_inspections) %></p>
            <p class="metric-detail">Source or observer turns reporting cached input.</p>
          </article>

          <article class="metric-card ds-panel">
            <p class="metric-label">Providers</p>
            <p class="metric-value numeric"><%= provider_count(@payload.session_inspections) %></p>
            <p class="metric-detail">Distinct external session platforms observed.</p>
          </article>
        </section>

        <section class="session-viewer-grid" id="session-summary-list">
          <aside class="session-filter-panel ds-panel">
            <div class="section-header">
              <div>
                <h2 class="section-title">Filters</h2>
                <p class="section-copy">Current provider and cache distribution.</p>
              </div>
            </div>

            <div class="filter-chip-list">
              <span class="ds-pill ds-pill-thread">All platforms</span>
              <span :for={platform <- platforms(@payload.session_inspections)} class="ds-pill">
                <%= platform %>
              </span>
              <span :if={@payload.session_inspections == []} class="muted">No platforms yet.</span>
            </div>
          </aside>

          <section class="section-card ds-panel session-summary-panel">
            <div class="section-header">
              <div>
                <h2 class="section-title">Observer summaries</h2>
                <p class="section-copy">Interpreted results first; raw session identifiers stay inside details.</p>
              </div>
            </div>

            <%= if @payload.session_inspections == [] do %>
              <p class="empty-state">No observer summaries have been captured.</p>
            <% else %>
              <div class="summary-grid">
                <article class="summary-card ds-session-card" :for={inspection <- @payload.session_inspections}>
                  <div class="summary-card-header">
                    <div class="issue-stack">
                      <span class="issue-id"><%= inspection.issue_identifier || inspection.issue_id %></span>
                      <span class="muted mono"><%= inspection.updated_at || "n/a" %></span>
                    </div>
                    <div class="summary-badge-row">
                      <span class={summary_state_class(inspection)}>
                        <%= summary_state_text(inspection) %>
                      </span>
                      <span class={cache_badge_class(inspection.cache_analysis)}>
                        <%= cache_badge_text("Source", inspection.cache_analysis) %>
                      </span>
                      <span :if={inspection.observer_cache_analysis} class={cache_badge_class(inspection.observer_cache_analysis)}>
                        <%= cache_badge_text("Observer", inspection.observer_cache_analysis) %>
                      </span>
                    </div>
                  </div>

                  <div class="summary-content-grid">
                    <section class="summary-result">
                      <h3>Observer result</h3>
                      <pre class="summary-text"><%= summary_body(inspection.summary_text || inspection.error) %></pre>
                    </section>

                    <aside class="summary-side-panel">
                      <div :if={inspection.latest_user_query} class="summary-query">
                        <span>Latest query</span>
                        <p><%= compact_line(inspection.latest_user_query) %></p>
                      </div>

                      <dl class="summary-meta ds-meta-grid">
                        <div class="ds-meta-item">
                          <dt>Platform</dt>
                          <dd class="mono"><%= inspection.platform || "unknown" %></dd>
                        </div>
                        <div class="ds-meta-item">
                          <dt>Model</dt>
                          <dd class="mono"><%= source_model(inspection.source_session) %></dd>
                        </div>
                        <div class="ds-meta-item">
                          <dt>Status</dt>
                          <dd class="mono"><%= inspection.status || source_status(inspection.source_session) %></dd>
                        </div>
                        <div class="ds-meta-item">
                          <dt>Clone</dt>
                          <dd class="mono"><%= observer_clone_strategy(inspection.observer_session) %></dd>
                        </div>
                        <div class="ds-meta-item">
                          <dt>Observer turn</dt>
                          <dd class="mono" title={observer_turn_id(inspection.observer_turn)}>
                            <%= observer_turn_id(inspection.observer_turn) %>
                          </dd>
                        </div>
                      </dl>

                      <details class="summary-details">
                        <summary>Raw session details</summary>
                        <dl class="summary-details-list">
                          <div>
                            <dt>Source session</dt>
                            <dd class="mono"><%= source_session_id(inspection.source_session) %></dd>
                          </div>
                          <div>
                            <dt>Source path</dt>
                            <dd class="mono"><%= source_path(inspection.source_session) %></dd>
                          </div>
                          <div>
                            <dt>Observer thread</dt>
                            <dd class="mono"><%= observer_thread_id(inspection.observer_turn, inspection.observer_session) %></dd>
                          </div>
                          <div>
                            <dt>Inspection</dt>
                            <dd class="mono"><%= inspection.inspection_id || "n/a" %></dd>
                          </div>
                        </dl>
                      </details>
                    </aside>
                  </div>
                </article>
              </div>
            <% end %>
          </section>
        </section>
      <% end %>
    </section>
    """
  end

  defp load_payload do
    Presenter.state_payload(orchestrator(), snapshot_timeout_ms())
  end

  defp orchestrator do
    Endpoint.config(:orchestrator) || SymphonyElixir.Orchestrator
  end

  defp snapshot_timeout_ms do
    Endpoint.config(:snapshot_timeout_ms) || 15_000
  end

  defp cache_hit_count(inspections) do
    Enum.count(inspections, fn inspection ->
      cache_hit?(inspection.cache_analysis) or cache_hit?(inspection.observer_cache_analysis)
    end)
  end

  defp cache_hit?(%{cache_hit?: true}), do: true
  defp cache_hit?(_cache_analysis), do: false

  defp provider_count(inspections), do: inspections |> platforms() |> length()

  defp platforms(inspections) do
    inspections
    |> Enum.map(&(&1.platform || "unknown"))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp summary_state_class(%{error: error}) when not is_nil(error),
    do: "summary-state summary-state-failed ds-pill ds-pill-danger"

  defp summary_state_class(%{observer: true, summary_text: summary_text}) when is_binary(summary_text),
    do: "summary-state summary-state-ready ds-pill ds-pill-cache"

  defp summary_state_class(_inspection), do: "summary-state summary-state-pending ds-pill ds-pill-warning"

  defp summary_state_text(%{error: error}) when not is_nil(error), do: "Failed"
  defp summary_state_text(%{observer: true, summary_text: summary_text}) when is_binary(summary_text), do: "Summarized"
  defp summary_state_text(_inspection), do: "Pending"

  defp cache_badge_class(%{cache_hit?: true}), do: "cache-badge cache-badge-hit ds-pill ds-pill-cache"
  defp cache_badge_class(_cache_analysis), do: "cache-badge ds-pill"

  defp cache_badge_text(label, %{cache_hit?: true, cache_hit_ratio: ratio}) when is_number(ratio) do
    "#{label} cache #{round(ratio * 100)}%"
  end

  defp cache_badge_text(label, %{cache_hit?: true}), do: "#{label} cache hit"
  defp cache_badge_text(label, _cache_analysis), do: "No #{String.downcase(label)} cache"

  defp summary_body(nil), do: "n/a"

  defp summary_body(summary_text) do
    summary_text
    |> to_string()
    |> String.trim()
  end

  defp compact_line(nil), do: "n/a"

  defp compact_line(summary_text) do
    summary_text
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp source_model(%{model: model}) when is_binary(model), do: model
  defp source_model(%{"model" => model}) when is_binary(model), do: model
  defp source_model(_source_session), do: "unknown"

  defp source_status(%{status: status}) when is_binary(status), do: status
  defp source_status(%{"status" => status}) when is_binary(status), do: status
  defp source_status(_source_session), do: "n/a"

  defp source_session_id(%{id: id}) when is_binary(id), do: id
  defp source_session_id(%{"id" => id}) when is_binary(id), do: id
  defp source_session_id(_source_session), do: "n/a"

  defp source_path(%{path: path}) when is_binary(path), do: path
  defp source_path(%{"path" => path}) when is_binary(path), do: path
  defp source_path(_source_session), do: "n/a"

  defp observer_turn_id(%{turn_id: turn_id}) when is_binary(turn_id), do: turn_id
  defp observer_turn_id(%{session_id: session_id}) when is_binary(session_id), do: session_id
  defp observer_turn_id(_observer_turn), do: "n/a"

  defp observer_thread_id(%{thread_id: thread_id}, _observer_session) when is_binary(thread_id), do: thread_id
  defp observer_thread_id(_observer_turn, %{thread_id: thread_id}) when is_binary(thread_id), do: thread_id
  defp observer_thread_id(_observer_turn, %{"thread_id" => thread_id}) when is_binary(thread_id), do: thread_id
  defp observer_thread_id(_observer_turn, _observer_session), do: "n/a"

  defp observer_clone_strategy(%{clone_strategy: clone_strategy}), do: to_string(clone_strategy)
  defp observer_clone_strategy(%{"clone_strategy" => clone_strategy}), do: to_string(clone_strategy)
  defp observer_clone_strategy(_observer_session), do: "n/a"
end
