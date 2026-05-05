// Main App — Session Viewer
const { useState, useEffect, useRef, useMemo, useCallback } = React;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "lang": "en",
  "theme": "dark",
  "providerFocus": "all",
  "showBranch": true
}/*EDITMODE-END*/;

function App() {
  const [tw, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const lang = tw.lang;

  // apply theme + lang to <body>
  useEffect(() => {
    document.body.dataset.theme = tw.theme;
    document.body.dataset.lang = tw.lang;
  }, [tw.theme, tw.lang]);

  const [filter, setFilter] = useState("all");
  const [activeId, setActiveId] = useState(window.SESSIONS[0].id);
  const [modalOpen, setModalOpen] = useState(false);
  const [pipeTab, setPipeTab] = useState("summary"); // summary | request | pipe
  const [cliLines, setCliLines] = useState(() => seedCli(lang));
  const [cliInput, setCliInput] = useState("");
  const [running, setRunning] = useState(false);
  const [presetId, setPresetId] = useState("user");

  // filter sessions
  const sessions = useMemo(() => {
    let arr = window.SESSIONS;
    if (tw.providerFocus !== "all") {
      arr = arr.filter(s => s.provider === tw.providerFocus);
    }
    if (filter === "live")     arr = arr.filter(s => s.status === "live");
    else if (filter === "idle")arr = arr.filter(s => s.status === "idle");
    else if (filter === "done")arr = arr.filter(s => s.status === "done");
    else if (filter === "branched") arr = arr.filter(s => s.hasBranch);
    return arr;
  }, [filter, tw.providerFocus]);

  const active = useMemo(() =>
    sessions.find(s => s.id === activeId) || sessions[0] || window.SESSIONS[0],
    [sessions, activeId]
  );

  // when filter removes the active session, snap to first
  useEffect(() => {
    if (sessions.length && !sessions.find(s => s.id === activeId)) {
      setActiveId(sessions[0].id);
    }
  }, [sessions, activeId]);

  // simulated branch run
  const runBranch = useCallback((presetOverride) => {
    const pid = presetOverride || presetId;
    const preset = window.PRESETS.find(p => p.id === pid) || window.PRESETS[0];
    setRunning(true);
    setModalOpen(false);
    setPipeTab("pipe");
    appendCli({
      cls: "in", pf: "›",
      msg: `branch ${active.id} --preset ${preset.id} --perspective ${preset.perspective} --pipe mcp`,
    });
    setTimeout(() => appendCli({
      cls: "out", pf: "→",
      msg: `forking thread at checkpoint ckpt_${active.id.toLowerCase()}_${active.turns}`,
    }), 350);
    setTimeout(() => appendCli({
      cls: "out", pf: "→",
      msg: `attached prefix · ${(active.cached / 1000).toFixed(1)}k cached tokens reused`,
    }), 700);
    setTimeout(() => appendCli({
      cls: "ok", pf: "✓",
      msg: `cache hit · TTFT 142ms · prefill skipped (saved $${(active.cached * 0.000003).toFixed(4)})`,
    }), 1100);
    setTimeout(() => appendCli({
      cls: "out", pf: "→",
      msg: `streaming evaluation from ${active.model}…`,
    }), 1500);
    setTimeout(() => {
      appendCli({
        cls: "out", pf: " ",
        msg: "",
        block: lang === "kr" ? active.summary_kr : active.summary_en,
      });
      appendCli({
        cls: "ok", pf: "✓",
        msg: `piped to mcp://desk-orchestrator/sessions/${active.id}/summary`,
      });
      setRunning(false);
    }, 2400);
  }, [active, lang, presetId]);

  // Test: live subscribe (websocket / SSE feasibility check)
  const testSubscribe = useCallback(() => {
    setPipeTab("pipe");
    appendCli({ cls: "in", pf: "›", msg: `test subscribe --session ${active.id} --transport sse` });
    setTimeout(() => appendCli({ cls: "out", pf: "→", msg: `dialing wss://desk-orchestrator/sessions/${active.id}/stream …` }), 250);
    setTimeout(() => appendCli({ cls: "out", pf: "→", msg: `tcp ok · tls ok · auth ok (token age 4m12s)` }), 600);
    setTimeout(() => appendCli({ cls: "out", pf: "→", msg: `subscribe { thread_id: "${active.id.toLowerCase()}_main", events: ["turn","tool_call","checkpoint"] }` }), 950);
    setTimeout(() => appendCli({ cls: "ok", pf: "✓", msg: `subscribed · 1 listener · backpressure 0 · roundtrip 38ms` }), 1300);
    setTimeout(() => appendCli({ cls: "out", pf: "⟶", msg: `live event #${active.turns + 1} · tool_call: edit_file · 142B` }), 1700);
    setTimeout(() => appendCli({ cls: "ok", pf: "✓", msg: `LIVE_SUBSCRIBE_OK — feed healthy, ready for branch` }), 2050);
  }, [active]);

  // Test: summary readiness (can we fork & summarize this session right now?)
  const testReadiness = useCallback(() => {
    setPipeTab("pipe");
    appendCli({ cls: "in", pf: "›", msg: `test summary-readiness --session ${active.id}` });
    setTimeout(() => appendCli({ cls: "out", pf: "→", msg: `[1/5] checkpoint exists           · ckpt_${active.id.toLowerCase()}_${active.turns} ✓` }), 220);
    setTimeout(() => appendCli({ cls: "out", pf: "→", msg: `[2/5] prefix hash addressable     · ${(active.cached/1000).toFixed(1)}k tok ✓` }), 480);
    setTimeout(() => appendCli({ cls: "out", pf: "→", msg: `[3/5] provider quota              · ${active.provider} ${active.provider==='anthropic'?'432k/1M':'78k/240k'} rpm ✓` }), 760);
    setTimeout(() => appendCli({ cls: "out", pf: "→", msg: `[4/5] routing key collision-free · prompt_cache_key=${active.id.toLowerCase()}_main ✓` }), 1040);
    setTimeout(() => appendCli({ cls: "out", pf: "→", msg: `[5/5] dry-run prefill              · expected cache_read=${active.cached.toLocaleString()} tok · ttft~142ms ✓` }), 1340);
    setTimeout(() => appendCli({ cls: "ok", pf: "✓", msg: `SUMMARY_READY — branch will hit cache · est. cost $${(active.cost*0.05).toFixed(4)}` }), 1640);
  }, [active]);

  function appendCli(line) {
    setCliLines(L => [...L, { ...line, ts: tsNow() }]);
  }

  function handleCliSubmit(e) {
    e.preventDefault();
    const v = cliInput.trim();
    if (!v) return;
    setCliInput("");
    appendCli({ cls: "in", pf: "›", msg: v });
    if (/branch/i.test(v)) {
      runBranch("summarize");
    } else if (/help/i.test(v)) {
      appendCli({ cls: "out", pf: "→", msg: "commands: branch <id>, summarize <id>, pipe mcp|cli, list" });
    } else if (/list/i.test(v)) {
      appendCli({ cls: "out", pf: "→", msg: `${sessions.length} sessions across ${new Set(sessions.map(s => s.host)).size} hosts` });
    } else {
      appendCli({ cls: "warn", pf: "!", msg: `unknown command: ${v}` });
    }
  }

  // keyboard: ⌘B to branch
  useEffect(() => {
    function onKey(e) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "b") {
        e.preventDefault();
        setModalOpen(true);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="win">
      {/* ── Title bar ─────────────────────────────────── */}
      <div className="titlebar">
        <div className="traffic"><span></span><span></span><span></span></div>
        <div className="crumbs">
          <span>session-viewer</span>
          <span className="sep">/</span>
          <b>workspace</b>
          <span className="sep">/</span>
          <span className="here">{active.host}</span>
          <span className="sep">·</span>
          <span className="here">{active.id}</span>
        </div>
        <div className="titlebar-spacer"></div>
        <a className="tb-link" href="Concept.html">{lang === "kr" ? "개념 가이드" : "concept guide"} →</a>
        <div className="tb-pill"><span className="dot"></span>3 hosts online</div>
        <div className="tb-pill"><span className={`dot ${running ? "warn" : ""}`}></span>{running ? "branching…" : "idle"}</div>
      </div>

      {/* ── Three-pane layout ─────────────────────────── */}
      <div className="panes">
        {/* LEFT — Session list */}
        <aside className="pane">
          <div className="pane-hdr">
            <div className="ttl"><b>{t("pane_sessions", lang)}</b></div>
            <div className="ct">{sessions.length}/{window.SESSIONS.length}</div>
          </div>
          <div className="filter-bar">
            {["all", "live", "idle", "done", "branched"].map(k => (
              <button
                key={k}
                className={`filter-chip ${filter === k ? "on" : ""}`}
                onClick={() => setFilter(k)}
              >
                {t(`filter_${k}`, lang)}
              </button>
            ))}
          </div>
          <div className="session-list">
            {sessions.map(s => (
              <SessionRow
                key={s.id}
                s={s}
                lang={lang}
                active={s.id === active.id}
                onClick={() => setActiveId(s.id)}
              />
            ))}
            {sessions.length === 0 && (
              <div style={{ padding: 24, textAlign: "center", color: "var(--ink-3)", fontFamily: "var(--mono)", fontSize: 11 }}>
                no sessions match
              </div>
            )}
          </div>
        </aside>

        {/* MIDDLE — Detail / thread */}
        <main className="pane pane-mid">
          <div className="detail-hdr">
            <div className="dh-top">
              <span className="id">#{String(active.num).padStart(3, "0")} · {active.id}</span>
              <span className="host">{active.host}</span>
              <span className="model"><ProviderDot provider={active.provider} /> {active.model}</span>
              <StatusPill status={active.status} lang={lang} />
              <span style={{ display: "inline-flex", alignItems: "center", gap: 5, fontFamily: "var(--mono)", fontSize: 10.5, color: "var(--accent)", padding: "2px 7px", border: "1px solid color-mix(in oklch, var(--accent), transparent 70%)", borderRadius: 999, background: "color-mix(in oklch, var(--accent), transparent 90%)" }}>
                <span style={{ width: 5, height: 5, borderRadius: "50%", background: "var(--accent)" }}></span>
                {t("cache_status_ok", lang)}
              </span>
              <span style={{ marginLeft: "auto", color: "var(--ink-3)" }}>started {active.started}</span>
            </div>
            <h1 className="dh-title">{lang === "kr" ? active.title_kr : active.title_en}</h1>
            <div className="dh-actions">
              <button className="btn primary" onClick={() => setModalOpen(true)}>
                <Icon name="branch" />
                {t("btn_branch", lang)}
                <span className="kbd">⌘B</span>
              </button>
              <button className="btn" onClick={() => { setPipeTab("pipe"); appendCli({ cls: "in", pf: "›", msg: `pipe ${active.id} --target mcp` }); setTimeout(() => appendCli({ cls: "ok", pf: "✓", msg: `forwarded summary to mcp://desk-orchestrator/sessions/${active.id}` }), 500); }}>
                <Icon name="mcp" />
                {t("btn_pipe_mcp", lang)}
              </button>
              <button className="btn" onClick={() => { setPipeTab("pipe"); appendCli({ cls: "in", pf: "›", msg: `pipe ${active.id} --target cli` }); setTimeout(() => appendCli({ cls: "ok", pf: "✓", msg: `wrote ~/.session-viewer/exports/${active.id}.json` }), 400); }}>
                <Icon name="cli" />
                {t("btn_pipe_cli", lang)}
              </button>
              <button className="btn" onClick={testSubscribe} title={t("btn_test_subscribe", lang)}>
                <Icon name="radio" />
                {t("btn_test_subscribe", lang)}
              </button>
              <button className="btn" onClick={testReadiness} title={t("btn_test_ready", lang)}>
                <Icon name="flask" />
                {t("btn_test_ready", lang)}
              </button>
              <button className="btn ghost">
                <Icon name="file" />
                {t("btn_export", lang)}
              </button>
            </div>
          </div>

          {/* Metrics strip — cache reduced to a tiny status dot in dh-top */}
          <div className="metrics">
            <Metric
              label={t("metric_tokens", lang)}
              value={active.tokens.toLocaleString()}
              sub={`${active.turns} turns`}
            />
            <Metric
              label={t("metric_branch", lang)}
              value={active.hasBranch ? "−87%" : "—"}
              sub={active.hasBranch ? "vs naive prefill" : "no branch"}
              tone={active.hasBranch ? "violet" : ""}
            />
            <Metric
              label={t("metric_cost", lang)}
              value={`$${active.cost.toFixed(3)}`}
              sub={`saved $${((active.cached / active.tokens) * active.cost * 9).toFixed(2)}`}
            />
          </div>

          {/* Thread visualization */}
          <div className="thread-wrap">
            {/* Main thread */}
            <div className="thread-section">
              <div className="ts-hdr">
                <span className="ts-tag main">{t("thread_main", lang)}</span>
                <span className="ts-id">thread_id: <b>{active.id.toLowerCase()}_main</b></span>
                {active.status === "live" && <span className="live-dot"></span>}
                <span style={{ marginLeft: "auto", fontFamily: "var(--mono)", fontSize: 10.5, color: "var(--ink-3)" }}>
                  {t("prefix_label", lang)}
                </span>
              </div>

              <PrefixBar session={active} />

              <div className="turns">
                {window.TURNS_DEFAULT.map((tn, i) => (
                  <Turn key={i} turn={tn} idx={i + 1} lang={lang} />
                ))}
              </div>
            </div>

            {/* Branch divider — main thread continues */}
            {active.hasBranch && tw.showBranch && (
              <>
                <div className="branch-divider">
                  <span className="arrow">⇢</span>
                  <span className="text">{t("branch_inserted_main", lang)}</span>
                </div>

                {/* Eval branch */}
                <div className="thread-section">
                  <div className="ts-hdr">
                    <span className="ts-tag branch">{t("thread_branch", lang)}</span>
                    <span className="ts-id">thread_id: <b>{active.id.toLowerCase()}_eval_b1</b></span>
                    <span style={{ marginLeft: "auto", fontFamily: "var(--mono)", fontSize: 10.5, color: "var(--accent)" }}>
                      ✓ {t("cache_hit_note", lang)}
                    </span>
                  </div>
                  <div className="branch-divider" style={{ margin: "0 0 10px" }}>
                    <span className="arrow">↳</span>
                    <span className="text">{t("branch_inserted_eval", lang)}</span>
                  </div>
                  <div className="turns">
                    <Turn
                      lang={lang}
                      idx={window.TURNS_DEFAULT.length + 1}
                      turn={{
                        role: "sum",
                        body_en: `[SYSTEM EVAL] Summarize the session above into: (1) a short title, (2) one paragraph synopsis, (3) bulleted next-actions. Keep neutral tone, do not modify the source thread.`,
                        body_kr: `[시스템 평가] 위의 세션을 다음으로 요약: (1) 짧은 제목, (2) 한 단락 시놉시스, (3) 다음 조치사항 글머리표. 중립적 톤 유지, 원본 스레드 수정 금지.`,
                        tokens: 92,
                        cached: false,
                        live: true,
                      }}
                    />
                    <Turn
                      lang={lang}
                      idx={window.TURNS_DEFAULT.length + 2}
                      turn={{
                        role: "asst",
                        body_en: `Title — "${lang === "kr" ? active.title_kr : active.title_en}". Synopsis: ${(lang === "kr" ? active.summary_kr : active.summary_en).slice(0, 180)}…`,
                        body_kr: `제목 — "${active.title_kr}". 시놉시스: ${active.summary_kr.slice(0, 180)}…`,
                        tokens: 318,
                        cached: false,
                        live: false,
                      }}
                    />
                  </div>
                </div>
              </>
            )}
          </div>
        </main>

        {/* RIGHT — Branch panel + pipe */}
        <aside className="pane">
          <div className="pipe-tabs">
            <button className={`pipe-tab ${pipeTab === "summary" ? "on" : ""}`} onClick={() => setPipeTab("summary")}>
              {t("pipe_tab_summary", lang)}
            </button>
            <button className={`pipe-tab ${pipeTab === "request" ? "on" : ""}`} onClick={() => setPipeTab("request")}>
              {t("pipe_tab_request", lang)}
            </button>
            <button className={`pipe-tab ${pipeTab === "pipe" ? "on" : ""}`} onClick={() => setPipeTab("pipe")}>
              {t("pipe_tab_pipe", lang)}
            </button>
          </div>

          {pipeTab === "summary" && (
            <div className="branch-panel">
              <div className="branch-section">
                <h4>{t("notes_summary_title", lang)} <b>· {active.id}</b></h4>
                <div className="summary-card">
                  <div className="sc-ses">
                    <span className="id">#{String(active.num).padStart(3, "0")}</span>
                    <span>·</span>
                    <span><ProviderDot provider={active.provider} /></span>
                    <span>·</span>
                    <span>{active.duration}</span>
                  </div>
                  <h5 className="sc-title">{lang === "kr" ? active.title_kr : active.title_en}</h5>
                  <div className="sc-body">
                    <p>{lang === "kr" ? active.summary_kr : active.summary_en}</p>
                  </div>
                  <div className="sc-foot">
                    <span><b>✓ cache hit</b> · 142ms TTFT</span>
                    <span>{(active.cached / 1000).toFixed(1)}k tok reused</span>
                    <span>$0.0008</span>
                  </div>
                </div>
              </div>

              <div className="branch-section">
                <h4>{t("notes_actions", lang)}</h4>
                <ol style={{ margin: 0, paddingLeft: 18, fontSize: 12, lineHeight: 1.65, color: "var(--ink-2)" }}>
                  {(lang === "kr" ? active.actions_kr : active.actions_en).map((a, i) => (
                    <li key={i} style={{ marginBottom: 6 }}>{a}</li>
                  ))}
                </ol>
              </div>

              <div className="branch-section" style={{ borderBottom: 0 }}>
                <h4>provenance</h4>
                <pre className="code-pre" style={{ margin: 0 }}>
{`{
  "source_thread": "${active.id.toLowerCase()}_main",
  "fork_at_turn":  ${active.turns},
  "branch_thread": "${active.id.toLowerCase()}_eval_b1",
  "prefix_hash":   "0x${active.id.slice(2)}…a4f9",
  "cache_hit":     true,
  "cache_read_tokens": ${active.cached},
  "ttft_ms":       142,
  "model":         "${active.model}",
  "provider":      "${active.provider}"
}`}
                </pre>
              </div>
            </div>
          )}

          {pipeTab === "request" && (
            <div className="branch-panel">
              <div className="branch-section">
                <h4>{t("modal_title", lang)}</h4>
                <div className="req-form">
                  <div className="req-row">
                    <label>{t("field_session", lang)}</label>
                    <input value={`${active.id} · ${(lang === "kr" ? active.title_kr : active.title_en).slice(0, 38)}…`} readOnly />
                  </div>
                  <div className="req-row">
                    <label>{t("preset_perspective", lang)} — {t(`preset_perspective_${(window.PRESETS.find(p=>p.id===presetId)||{}).perspective||'user'}`, lang)}</label>
                    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 4 }}>
                      {window.PRESETS.map(p => (
                        <button key={p.id} className={`target-chip ${presetId===p.id?'on':''}`} onClick={()=>setPresetId(p.id)} style={{ flexDirection: "column", alignItems: "flex-start", padding: "7px 9px", gap: 2 }}>
                          <span style={{ display: "inline-flex", alignItems: "center", gap: 5, fontSize: 11 }}><Icon name={p.icon} size={11} /> {t(p.label, lang)}</span>
                          <span style={{ color: "var(--ink-3)", fontSize: 9.5, fontFamily: "var(--mono)", lineHeight: 1.3 }}>{t(p.tag, lang)}</span>
                        </button>
                      ))}
                    </div>
                  </div>
                  <div className="req-row">
                    <label>{t("field_prompt", lang)}</label>
                    <textarea key={presetId} defaultValue={t((window.PRESETS.find(p=>p.id===presetId)||{}).prompt || "preset_user", lang)} rows={5} />
                  </div>
                  <div className="req-row">
                    <label>{t("field_routing", lang)}</label>
                    <input defaultValue={`prompt_cache_key=${active.id.toLowerCase()}_main`} />
                  </div>
                  <div className="req-row">
                    <label>{t("field_target", lang)}</label>
                    <div className="target-grid">
                      <button className="target-chip on"><Icon name="mcp" /> mcp://desk-orch</button>
                      <button className="target-chip"><Icon name="cli" /> ~/.sv/exports</button>
                    </div>
                  </div>
                  <button className="btn primary" style={{ justifyContent: "center", marginTop: 6 }} onClick={() => runBranch(presetId)}>
                    <Icon name="play" /> {t("btn_run", lang)} <span className="kbd">↵</span>
                  </button>
                </div>
              </div>
            </div>
          )}

          {pipeTab === "pipe" && (
            <div className="cli">
              <div className="cli-out" id="cli-scroll">
                {cliLines.map((l, i) => (
                  <React.Fragment key={i}>
                    <div className={`l ${l.cls}`}>
                      <span className="ts">{l.ts}</span>
                      <span className="pf">{l.pf}</span>
                      <span className="msg">{l.msg}</span>
                    </div>
                    {l.block && <pre>{l.block}</pre>}
                  </React.Fragment>
                ))}
                {running && (
                  <div className="l out">
                    <span className="ts">{tsNow()}</span>
                    <span className="pf">⋯</span>
                    <span className="msg">streaming…</span>
                  </div>
                )}
              </div>
              <form className="cli-input" onSubmit={handleCliSubmit}>
                <span className="pf">›</span>
                <input
                  value={cliInput}
                  onChange={e => setCliInput(e.target.value)}
                  placeholder={t("cli_placeholder", lang)}
                  spellCheck="false"
                  autoComplete="off"
                />
              </form>
            </div>
          )}
        </aside>
      </div>

      {/* ── Status bar ────────────────────────────────── */}
      <div className="statusbar">
        <span><b>4</b> {t("status_running_branches", lang)}</span>
        <span><b>{(window.SESSIONS.reduce((a,s)=>a+s.cached,0)/1000).toFixed(0)}k</b> {t("status_kv_attached", lang)}</span>
        <span><b>148ms</b> {t("status_avg_ttft", lang)}</span>
        <div className="right">
          <span>{t("status_savings", lang)} <b>$12.84</b></span>
          <span>{tw.providerFocus === "all" ? "all providers" : tw.providerFocus}</span>
          <span>v0.4.2</span>
        </div>
      </div>

      {/* ── Modal ─────────────────────────────────────── */}
      {modalOpen && (
        <div className="modal-wrap" onClick={() => setModalOpen(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-hdr">
              <div>
                <h3>{t("modal_title", lang)}</h3>
                <div className="sub">{t("modal_sub", lang)}</div>
              </div>
              <button className="btn ghost" onClick={() => setModalOpen(false)}>
                <Icon name="close" />
              </button>
            </div>
            <div className="modal-body">
              <div className="req-form">
                <div className="req-row">
                  <label>{t("field_session", lang)}</label>
                  <input value={`${active.id} — ${lang === "kr" ? active.title_kr : active.title_en}`} readOnly />
                </div>

                <div className="req-row">
                  <label>{t("preset_perspective", lang)}</label>
                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6 }}>
                    {window.PRESETS.map(p => (
                      <button key={p.id} className={`target-chip ${presetId===p.id?'on':''}`} onClick={()=>setPresetId(p.id)} style={{ flexDirection: "column", alignItems: "flex-start", padding: "8px 10px", gap: 3 }}>
                        <span style={{ display: "inline-flex", alignItems: "center", gap: 6, fontSize: 12 }}><Icon name={p.icon} />{t(p.label, lang)}</span>
                        <span style={{ color: "var(--ink-3)", fontSize: 10, fontFamily: "var(--mono)" }}>{t(p.tag, lang)}</span>
                      </button>
                    ))}
                  </div>
                </div>

                <div className="req-row">
                  <label>{t("field_prompt", lang)}</label>
                  <textarea key={presetId} defaultValue={t((window.PRESETS.find(p=>p.id===presetId)||{}).prompt || "preset_user", lang)} rows={4} />
                </div>

                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
                  <div className="req-row">
                    <label>{t("field_routing", lang)}</label>
                    <input defaultValue={`${active.id.toLowerCase()}_main`} />
                  </div>
                  <div className="req-row">
                    <label>{t("field_target", lang)}</label>
                    <select defaultValue="mcp">
                      <option value="mcp">mcp://desk-orchestrator</option>
                      <option value="cli">~/.session-viewer/exports</option>
                      <option value="both">both</option>
                    </select>
                  </div>
                </div>

                <div style={{ display: "flex", gap: 8, padding: "10px 12px", background: "var(--bg-2)", border: "1px solid var(--line)", borderRadius: 8, fontFamily: "var(--mono)", fontSize: 10.5, color: "var(--ink-3)", lineHeight: 1.6 }}>
                  <Icon name="check" />
                  <div>
                    fork shares prefix with <b style={{ color: "var(--ink-2)" }}>{active.id.toLowerCase()}_main</b>.
                    expected: <b style={{ color: "var(--accent)" }}>cache_read = {active.cached.toLocaleString()} tok</b> ·
                    <b style={{ color: "var(--accent)" }}> ~90% discount</b> ·
                    main thread untouched.
                  </div>
                </div>
              </div>
            </div>
            <div className="modal-foot">
              <div className="info">routing: <b>cache-affinity-pinned</b></div>
              <button className="btn ghost" onClick={() => setModalOpen(false)}>{t("btn_cancel", lang)}</button>
              <button className="btn primary" onClick={() => runBranch(presetId)}>
                <Icon name="play" />
                {t("btn_run", lang)}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Tweaks panel ──────────────────────────────── */}
      <TweaksPanel title="Tweaks">
        <TweakSection label="Display" />
        <TweakRadio label="Theme" value={tw.theme} options={["dark", "light"]} onChange={v => setTweak("theme", v)} />
        <TweakRadio label="Language" value={tw.lang} options={["en", "kr"]} onChange={v => setTweak("lang", v)} />
        <TweakSection label="Filters" />
        <TweakRadio label="Provider focus" value={tw.providerFocus} options={["all", "anthropic", "openai", "gemini"]} onChange={v => setTweak("providerFocus", v)} />
        <TweakToggle label="Show branch in thread" value={tw.showBranch} onChange={v => setTweak("showBranch", v)} />
      </TweaksPanel>
    </div>
  );
}

// — utils —
function tsNow() {
  const d = new Date();
  return [d.getHours(), d.getMinutes(), d.getSeconds()]
    .map(n => String(n).padStart(2, "0")).join(":");
}

function seedCli(lang) {
  return [
    { ts: "08:42:01", cls: "out", pf: "→", msg: "session-viewer v0.4.2 — connected to 3 hosts" },
    { ts: "08:42:01", cls: "out", pf: "→", msg: "discovered 8 sessions · 5 active · 4 with branches" },
    { ts: "08:42:02", cls: "ok",  pf: "✓", msg: "kv-cache prefix index built · 161k tokens addressable" },
    { ts: "08:42:02", cls: "out", pf: "→", msg: "ready — type `help` for commands" },
  ];
}

ReactDOM.createRoot(document.getElementById("app")).render(<App />);
