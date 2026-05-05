// Reusable presentational components for the Session Viewer
const { useState, useEffect, useRef, useMemo } = React;

// — Status pill —
function StatusPill({ status, lang }) {
  const cls = `sr-status ${status}`;
  return (
    <span className={cls}>
      <span className="d"></span>
      {t(`status_${status}`, lang)}
    </span>
  );
}

// — Session row —
function SessionRow({ s, active, onClick, lang }) {
  return (
    <div
      className={`session-row ${active ? "active" : ""} ${s.hasBranch ? "has-branch" : ""}`}
      onClick={onClick}
    >
      <div className="sr-top">
        <span className="sr-id">{s.id}</span>
        <span className="sr-host">{s.host}</span>
        <StatusPill status={s.status} lang={lang} />
      </div>
      <h3 className="sr-title">{lang === "kr" ? s.title_kr : s.title_en}</h3>
      <div className="sr-meta">
        <span className="t">{s.duration}</span>
        <span className="sep">·</span>
        <span>{s.turns} turns</span>
        <span className="sep">·</span>
        <span>{(s.tokens / 1000).toFixed(1)}k tok</span>
      </div>
    </div>
  );
}

// — Prefix cache bar visualization —
function PrefixBar({ session }) {
  const cachedPct = Math.round((session.cached / session.tokens) * 100);
  const livePct = Math.max(2, 100 - cachedPct - (session.hasBranch ? 6 : 0));
  const evalPct = session.hasBranch ? 6 : 0;

  return (
    <>
      <div className="prefix-bar">
        <div className="pb-seg cached" style={{ width: `${cachedPct}%` }}>
          {cachedPct}% cached
        </div>
        <div className="pb-seg live" style={{ width: `${livePct}%` }}>
          live
        </div>
        {session.hasBranch && (
          <div className="pb-seg eval" style={{ width: `${evalPct}%` }}>
            eval
          </div>
        )}
      </div>
      <div className="pb-legend">
        <span><i style={{ background: "color-mix(in oklch, var(--accent), transparent 60%)" }}></i>cached prefix</span>
        <span><i style={{ background: "color-mix(in oklch, var(--accent-2), transparent 50%)" }}></i>live</span>
        {session.hasBranch && (
          <span><i style={{ background: "color-mix(in oklch, var(--violet), transparent 50%)" }}></i>eval branch</span>
        )}
      </div>
    </>
  );
}

// — Turn rendering —
function Turn({ turn, lang, idx }) {
  const role = turn.role;
  const cls = `turn ${role === "user" ? "user" : role === "tool" ? "tool" : role === "asst" ? "asst" : "sum"}`;
  return (
    <div className={cls}>
      <div className="role">
        {role === "system" ? "SYS" :
         role === "user"   ? "USER" :
         role === "asst"   ? "ASST" :
         role === "tool"   ? "TOOL" : "SUM"}
        <div style={{ marginTop: 4, color: "var(--ink-4)", fontWeight: 400 }}>
          #{String(idx).padStart(2, "0")}
        </div>
      </div>
      <div>
        {role === "tool" ? (
          <div className="body">
            <span className="toolcall">{turn.call}({turn.args})</span>
            <div style={{ marginTop: 6, color: "var(--ink-3)", fontSize: 11.5 }}>
              {lang === "kr" ? turn.body_kr : turn.body_en}
            </div>
          </div>
        ) : (
          <div className="body">{lang === "kr" ? turn.body_kr : turn.body_en}</div>
        )}
        <div className="meta">
          <span>{turn.tokens} tok</span>
          {turn.cached && <span className="ok">✓ cache hit</span>}
          {!turn.cached && turn.live && <span className="miss">live · prefill</span>}
          {!turn.cached && !turn.live && <span className="miss">cache miss</span>}
        </div>
      </div>
    </div>
  );
}

// — Metric tile —
function Metric({ label, value, sub, tone }) {
  return (
    <div className="metric">
      <div className="lbl">{label}</div>
      <div className={`val ${tone || ""}`}>{value}</div>
      {sub && <div className="sub">{sub}</div>}
    </div>
  );
}

// — Generic icon (tiny inline SVG) —
function Icon({ name, size = 14 }) {
  const stroke = "currentColor";
  const sw = 1.5;
  const paths = {
    branch: <g><circle cx="6" cy="3" r="2"/><circle cx="6" cy="13" r="2"/><circle cx="14" cy="8" r="2"/><path d="M6 5v6"/><path d="M6 8h6"/></g>,
    summary: <g><path d="M3 4h12"/><path d="M3 8h10"/><path d="M3 12h7"/></g>,
    play: <g><path d="M5 3l9 5-9 5z" fill={stroke} stroke="none"/></g>,
    chevron: <g><path d="M6 4l4 4-4 4"/></g>,
    pipe: <g><path d="M3 8h10"/><path d="M10 5l3 3-3 3"/></g>,
    mcp: <g><rect x="3" y="4" width="10" height="8" rx="1.5"/><path d="M5 8h6"/><circle cx="13" cy="8" r="1.2" fill={stroke} stroke="none"/></g>,
    cli: <g><path d="M3 5l3 3-3 3"/><path d="M8 11h6"/></g>,
    file: <g><path d="M4 2h6l3 3v9H4z"/><path d="M10 2v3h3"/></g>,
    spark: <g><path d="M8 2v4M8 10v4M2 8h4M10 8h4M4.5 4.5l2 2M9.5 9.5l2 2M4.5 11.5l2-2M9.5 6.5l2-2"/></g>,
    close: <g><path d="M4 4l8 8"/><path d="M12 4l-8 8"/></g>,
    search: <g><circle cx="7" cy="7" r="4"/><path d="M10 10l3 3"/></g>,
    copy: <g><rect x="3" y="3" width="8" height="8" rx="1"/><path d="M5 11v2h8V5h-2"/></g>,
    check: <g><path d="M3 8l3 3 7-7"/></g>,
    user: <g><circle cx="8" cy="6" r="2.5"/><path d="M3.5 13c.8-2.2 2.6-3.5 4.5-3.5s3.7 1.3 4.5 3.5"/></g>,
    wrench: <g><path d="M11 3a3 3 0 0 1 2 5.2L7 14l-2-2 5.8-6A3 3 0 0 1 11 3z"/><circle cx="11" cy="5.5" r="1.2" fill={stroke} stroke="none"/></g>,
    alert: <g><path d="M8 2l6.5 11h-13z"/><path d="M8 7v3"/><circle cx="8" cy="11.5" r=".7" fill={stroke} stroke="none"/></g>,
    radio: <g><circle cx="8" cy="8" r="5"/><circle cx="8" cy="8" r="1.6" fill={stroke} stroke="none"/></g>,
    flask: <g><path d="M6 2v4l-3 7a1 1 0 0 0 .9 1.5h8.2A1 1 0 0 0 13 13l-3-7V2"/><path d="M5 2h6"/></g>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
      {paths[name] || null}
    </svg>
  );
}

// — Provider logo dot —
function ProviderDot({ provider }) {
  const map = {
    openai:    { c: "#10a37f", l: "OAI" },
    anthropic: { c: "#d97757", l: "ANT" },
    gemini:    { c: "#4285f4", l: "GEM" },
  };
  const m = map[provider] || map.openai;
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 5,
      fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)",
    }}>
      <i style={{ width: 6, height: 6, borderRadius: "50%", background: m.c, display: "inline-block" }}></i>
      {m.l}
    </span>
  );
}

Object.assign(window, { StatusPill, SessionRow, PrefixBar, Turn, Metric, Icon, ProviderDot });
