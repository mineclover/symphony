/* Notes.html — perspective memo board
   Strong system-level distinction between MAIN thread (still running) and FORK threads (sidecars).
   Posts: 5 kinds — auto-summary | review | qa | exploration | decision
   Comments: tree, with 'ask fork' button on human comments to spawn a new fork response.
*/

const { useState, useEffect, useRef, useMemo, useCallback } = React;

// ───────────────────────────────────────────────────────────────────
// i18n
// ───────────────────────────────────────────────────────────────────
const STR = {
  brand_main: { en: "session-viewer", kr: "session-viewer" },
  brand_sub:  { en: "/ notes", kr: "/ 노트" },
  nav_viewer: { en: "viewer", kr: "뷰어" },
  nav_concept: { en: "concept", kr: "컨셉" },
  nav_notes: { en: "notes", kr: "노트" },
  live_label: { en: "1 main session active", kr: "1 main 진행 중" },

  page_title:    { en: "Reflection notes",
                   kr: "회고 노트" },
  page_sub:      { en: "Memo board for sessions: forks summarize, interpret, and review the running main thread; humans annotate, ask follow-ups, and pin decisions. The main thread keeps moving.",
                   kr: "세션 회고 게시판 — 포크가 메인 스레드를 요약·해석·리뷰하고, 사람이 코멘트로 다듬는다. 메인은 계속 진행 중." },
  crumb_proj: { en: "anthropic-research", kr: "anthropic-research" },

  rail_title: { en: "session", kr: "세션" },
  rail_count: { en: "notes", kr: "노트" },

  filter_all:    { en: "all",         kr: "전체" },
  filter_summary: { en: "summaries",  kr: "요약" },
  filter_review: { en: "reviews",     kr: "리뷰" },
  filter_qa:     { en: "Q&A",         kr: "Q&A" },
  filter_explore: { en: "exploration", kr: "탐색" },
  filter_decision: { en: "decisions", kr: "결정" },

  btn_new_summary: { en: "new summary", kr: "새 요약" },
  btn_new_note:    { en: "add note",    kr: "노트 추가" },
  btn_pin:         { en: "pin decision", kr: "결정 핀" },

  legend_main:  { en: "main thread", kr: "메인 스레드" },
  legend_fork:  { en: "fork (sidecar)", kr: "포크 (사이드카)" },
  legend_human: { en: "human note",  kr: "사람 노트" },

  ticker_title: { en: "main · live", kr: "메인 · 실시간" },
  ticker_note:  { en: "main thread is still running. these events do not enter notes — they appear here so reviewers stay in sync without re-attaching.",
                  kr: "메인 스레드는 계속 진행 중. 이 이벤트들은 노트에 들어가지 않음 — 리뷰어가 재진입 없이 흐름을 따라가기 위함." },
  ticker_paused: { en: "paused", kr: "일시정지" },
  ticker_running: { en: "streaming · 38ms ttft", kr: "스트리밍 중 · 38ms ttft" },

  kind_summary:  { en: "auto-summary",  kr: "자동 요약" },
  kind_review:   { en: "review",        kr: "리뷰" },
  kind_qa:       { en: "Q&A thread",    kr: "Q&A 스레드" },
  kind_exploration: { en: "exploration",   kr: "탐색 노트" },
  kind_decision: { en: "decision",      kr: "결정 기록" },

  origin_main:  { en: "main",  kr: "main" },
  origin_fork:  { en: "fork",  kr: "fork" },
  origin_human: { en: "human", kr: "human" },

  act_reply:     { en: "reply",       kr: "답글" },
  act_ask_fork:  { en: "ask fork",    kr: "포크에 질문" },
  act_pin:       { en: "pin",         kr: "핀" },
  act_resolve:   { en: "resolve",     kr: "해결" },

  compose_ph:    { en: "Add a note. Type @fork to spawn a sub-fork response.",
                   kr: "노트 추가. @fork 입력 시 하위 포크 답변이 생성됩니다." },
  compose_hint:  { en: "⌘+↵ to post · @fork creates sub-fork",
                   kr: "⌘+↵ 게시 · @fork 하위 포크 생성" },
  compose_post:  { en: "post", kr: "게시" },
  compose_ask:   { en: "post + ask fork", kr: "게시 + 포크 질문" },

  rubric_clarity: { en: "clarity", kr: "명확성" },
  rubric_accuracy:{ en: "accuracy", kr: "정확성" },
  rubric_useful:  { en: "useful",   kr: "유용함" },
  rubric_safe:    { en: "safe",     kr: "안전" },

  decision_lbl:   { en: "DECISION PINNED", kr: "결정 핀" },
  date_today:     { en: "today",     kr: "오늘" },
  date_yest:      { en: "yesterday", kr: "어제" },
  date_2dago:     { en: "2 days ago", kr: "2일 전" },

  thinking:       { en: "fork thinking…", kr: "포크 생각 중…" },
};
const t = (key, lang) => (STR[key] && STR[key][lang]) || key;

// ───────────────────────────────────────────────────────────────────
// Icons
// ───────────────────────────────────────────────────────────────────
const Ico = ({ name, size = 12 }) => {
  const p = {
    summary:  "M3 4h10M3 8h10M3 12h6",
    pin:      "M8 1v8M5 9h6M6 9v5l2 1 2-1V9",
    review:   "M2 4l3 3 4-5",
    qa:       "M3 3h10v7H6l-3 3V3z",
    fork:     "M5 2v3a3 3 0 003 3v6M5 2a1.5 1.5 0 100 3 1.5 1.5 0 000-3zM11 2v3a3 3 0 01-3 3M11 2a1.5 1.5 0 110 3 1.5 1.5 0 010-3zM8 14a1.5 1.5 0 100-3 1.5 1.5 0 000 3z",
    plus:     "M8 3v10M3 8h10",
    explore:  "M8 2a6 6 0 11-4.24 10.24M8 2v3M8 2L6 4M8 2l2 2",
    chat:     "M3 3h10v7H6l-3 3V3z",
    check:    "M3 8l3 3 7-7",
    arrow:    "M5 8h6M8 5l3 3-3 3",
    sparkle:  "M8 2v4M8 10v4M2 8h4M10 8h4",
    edit:     "M3 13h3l7-7-3-3-7 7v3z",
    dots:     "M4 8h.01M8 8h.01M12 8h.01",
    play:     "M5 3l7 5-7 5V3z",
    sun:      "M8 4v0M8 12v0M4 8h0M12 8h0M5 5l0 0M11 11l0 0M5 11l0 0M11 5l0 0M8 6a2 2 0 100 4 2 2 0 000-4z",
    moon:     "M11 9a4 4 0 11-4-7 5 5 0 004 7z",
    bot:      "M4 6h8v6H4V6zM6 4h4M6 8h.01M10 8h.01",
  }[name];
  return (
    <svg className="ico" width={size} height={size} viewBox="0 0 16 16"
         fill="none" stroke="currentColor" strokeWidth="1.4"
         strokeLinecap="round" strokeLinejoin="round">
      <path d={p}/>
    </svg>
  );
};

const KIND_ICON = {
  summary: "summary",
  review: "review",
  qa: "qa",
  exploration: "explore",
  decision: "pin",
};

// ───────────────────────────────────────────────────────────────────
// Mock data — sessions + posts + comments
// ───────────────────────────────────────────────────────────────────
const SESSIONS = [
  { id: "S-7421",
    title_en: "Investigate prefill regression in claude-sonnet-4-5",
    title_kr: "claude-sonnet-4-5 prefill 회귀 분석",
    turns: 47, status: "running", note_ct: 6 },
  { id: "S-7388",
    title_en: "Refactor MCP transport layer for streaming",
    title_kr: "MCP 트랜스포트 레이어 스트리밍 리팩토링",
    turns: 31, status: "running", note_ct: 3 },
  { id: "S-7351",
    title_en: "Eval harness — judge calibration",
    title_kr: "Eval 하네스 — 저지 캘리브레이션",
    turns: 22, status: "paused", note_ct: 2 },
  { id: "S-7299",
    title_en: "Inference cost dashboard",
    title_kr: "추론 비용 대시보드",
    turns: 18, status: "done", note_ct: 1 },
];

const POSTS = [
  // ─── DAY: today ─────────────────────────────────────
  {
    id: "p1", date: "today", ts: "14:32",
    kind: "summary", origin: "fork",
    forkId: "fork_7421_summarize_v3",
    perspective: "user-task recap",
    title_en: "Engineer asked: why is prefill 4× slower on sonnet-4-5 vs sonnet-4?",
    title_kr: "엔지니어 질문: 왜 sonnet-4-5의 prefill이 sonnet-4보다 4배 느린가?",
    body_en: [
      "User's stated goal: reproduce the regression deterministically and isolate whether it's a server-side scheduling issue or a tokenizer/cache-key change.",
      "By turn 32 they had narrowed it to: requests with prompt_cache_key set + system prompts > 8k tokens hit a slow path. They want a minimal repro before filing.",
      "Outstanding: confirm with a 2k-token system prompt control; check if the slow path also affects sonnet-4 under load.",
    ],
    body_kr: [
      "사용자 목표: 회귀 현상을 결정론적으로 재현하고, 이게 서버 스케줄링 문제인지 토크나이저/캐시 키 변경 문제인지 분리.",
      "32턴 시점에 좁혀진 것: prompt_cache_key가 설정된 요청 + 시스템 프롬프트 8k 토큰 초과 시 slow path 진입. 보고 전 최소 재현 필요.",
      "남은 작업: 2k 토큰 시스템 프롬프트로 대조군 확인; sonnet-4도 부하 시 같은 slow path 진입하는지 확인.",
    ],
    cost: 0.0042, tokens_read: 14782, tokens_gen: 412,
    comments: [
      {
        id: "c1a", who: "human", author: "Jiwoo",
        ts: "14:38",
        text_en: "Good capture. But the user *also* spent ~6 turns staring at flame graphs that didn't end up mattering — should that be in the recap or filtered out as noise?",
        text_kr: "잘 잡았네. 근데 사용자가 별로 안 중요한 flame graph를 6턴 동안 봤는데 — 이거 회고에 넣어야 하나, 노이즈로 빼야 하나?",
        children: [
          {
            id: "c1b", who: "fork", author: "fork_7421_summarize_v3", source: "follow-up",
            ts: "14:39",
            text_en: "Reasonable to keep it. Flame graph time was wasted in retrospect, but it was the user's actual debugging arc — recap should reflect what they tried, not just what worked. I can re-emit with a `dead-ends:` section.",
            text_kr: "유지하는 게 합리적. 결과적으론 헛수고였지만 사용자의 실제 디버깅 흐름이었음 — 회고는 무엇이 통했나가 아니라 무엇을 시도했나를 반영해야. `dead-ends:` 섹션 추가해서 재발행 가능.",
          },
          {
            id: "c1c", who: "human", author: "Jiwoo",
            ts: "14:41",
            text_en: "Yeah do that. Also pin this as the canonical recap for the regression bug.",
            text_kr: "그렇게 해. 그리고 이걸 회귀 버그 정식 회고로 핀 고정.",
          },
        ],
      },
    ],
  },

  {
    id: "p2", date: "today", ts: "14:18",
    kind: "exploration", origin: "human",
    author: "Jiwoo",
    title_en: "Was the slow path always there or did it appear with a deploy?",
    title_kr: "slow path가 원래 있었나, 아니면 어떤 배포로 생긴 건가?",
    body_en: [
      "Looking at the recap, fork is confident it's the (cache_key + long system) combo. But I want to know *when* this started. Asking fork to bisect deploy logs from the last 14 days.",
    ],
    body_kr: [
      "회고를 보니 fork는 (cache_key + 긴 시스템 프롬프트) 조합이라고 확신하는데, 이게 *언제부터* 시작됐는지 알고 싶다. 최근 14일 배포 로그 bisect 요청.",
    ],
    comments: [
      {
        id: "c2a", who: "fork", author: "fork_7421_bisect_v1", source: "ask-fork",
        ts: "14:21",
        text_en: "Bisected. Slow path appeared on 2026-04-28 with the rollout of `pcache-v3` (changes to KV layout). Sonnet-4 was rolled forward 6 days later — that's why it shows the same symptom under load now.",
        text_kr: "Bisect 완료. Slow path는 2026-04-28 `pcache-v3` 롤아웃 (KV 레이아웃 변경) 시점에 등장. Sonnet-4는 6일 뒤 동일 빌드로 롤아웃 — 그래서 부하 시 같은 증상.",
        children: [
          {
            id: "c2b", who: "human", author: "Jiwoo",
            ts: "14:24",
            text_en: "Pin this. We just answered \"is it new\" definitively. @fork can you also check if pcache-v3 had a load test for the > 8k system prompt regime?",
            text_kr: "핀 고정. \"새로 생긴 거냐\"에 답이 나왔다. @fork pcache-v3가 8k 초과 시스템 프롬프트 영역에 부하 테스트 했는지 확인 가능?",
          },
          {
            id: "c2c", who: "fork", author: "fork_7421_bisect_v2", source: "ask-fork",
            ts: "14:26",
            text_en: "Checked rollout doc. Load tests were 512–4k system prompts only. > 8k regime was untested. Filing this as a gap.",
            text_kr: "롤아웃 문서 확인. 부하 테스트는 512–4k 시스템 프롬프트만. 8k 초과 영역은 미테스트. 갭으로 파일링.",
          },
        ],
      },
    ],
  },

  {
    id: "p3", date: "today", ts: "13:55",
    kind: "decision", origin: "human",
    author: "Jiwoo",
    decision_what_en: "Don't roll back pcache-v3. Patch forward.",
    decision_what_kr: "pcache-v3 롤백하지 않음. 패치 포워드.",
    decision_why_en: "Rollback risks reintroducing a different bug fixed in v3 (cache poisoning under reconnect). The slow path affects < 0.4% of requests; a forward patch to honor the > 8k regime is lower risk.",
    decision_why_kr: "롤백 시 v3에서 수정된 다른 버그(재연결 시 캐시 오염) 재발 위험. Slow path는 전체 요청의 0.4% 미만 영향; 8k 초과 영역 처리하는 forward patch가 더 안전.",
    related_posts: ["p1", "p2"],
    comments: [],
  },

  // ─── DAY: yesterday ─────────────────────────────────
  {
    id: "p4", date: "yest", ts: "17:42",
    kind: "review", origin: "fork",
    forkId: "fork_7421_judge_v1",
    perspective: "LLM-as-judge",
    title_en: "Review: agent's debugging trajectory in S-7421 (turns 1–32)",
    title_kr: "리뷰: S-7421의 에이전트 디버깅 궤적 (1–32턴)",
    body_en: [
      "Scoring rubric on agent's behavior in the main thread. The agent did good first-principles work but spent excess turns on instrumentation that the user could have skipped.",
    ],
    body_kr: [
      "메인 스레드에서 에이전트 행동 채점. 에이전트가 first-principles 사고는 잘했지만, 사용자가 건너뛸 수 있었던 instrumentation에 너무 많은 턴 소비.",
    ],
    rubric: { clarity: 8, accuracy: 9, useful: 6, safe: 10 },
    comments: [
      {
        id: "c4a", who: "human", author: "Hyun",
        ts: "17:51",
        text_en: "Useful=6 feels low. The instrumentation work *did* end up surfacing the > 8k regime as the trigger. Without those turns we wouldn't have the recap p1 has now.",
        text_kr: "Useful=6는 좀 박한 듯. 그 instrumentation 작업이 결국 8k 초과 영역을 트리거로 드러내준 거잖아. 그 턴들 없었으면 p1 같은 회고도 없었을 거.",
        children: [
          {
            id: "c4b", who: "fork", author: "fork_7421_judge_v2", source: "ask-fork",
            ts: "17:54",
            text_en: "Fair counter. Re-scoring useful=8 with this rationale: the work was indirect but load-bearing. Updating rubric notes.",
            text_kr: "타당한 반론. 이 근거로 useful=8 재채점: 우회적이었지만 본질적 기여. Rubric 노트 업데이트.",
          },
        ],
      },
    ],
  },

  {
    id: "p5", date: "yest", ts: "11:08",
    kind: "qa", origin: "human",
    author: "Hyun",
    title_en: "Q&A: ask fork to enumerate every config flag the main thread mutated",
    title_kr: "Q&A: 메인 스레드가 변경한 모든 config flag 나열 요청",
    body_en: [
      "Want a side-by-side of what config the main agent touched, from a system perspective — not the user's narrative.",
    ],
    body_kr: [
      "메인 에이전트가 건드린 config를 시스템 관점에서 나열 — 사용자 서사 말고.",
    ],
    comments: [
      {
        id: "c5a", who: "fork", author: "fork_7421_sysview_v1", source: "initial",
        ts: "11:10",
        text_en: "From system POV, main thread set: `prefill.batch_size=8→32`, `routing.cache_key=experiment-7421`, `tracing.flame=on`, `kv.layout=v2 (overridden)`. Restored on turn 28 except `cache_key` (still set).",
        text_kr: "시스템 관점에서 메인 스레드가 설정한 항목: `prefill.batch_size=8→32`, `routing.cache_key=experiment-7421`, `tracing.flame=on`, `kv.layout=v2 (override)`. 28턴에 복원했으나 `cache_key`는 유지 중.",
        children: [
          {
            id: "c5b", who: "human", author: "Hyun",
            ts: "11:14",
            text_en: "`cache_key` still set is a leak — main thread should clear it before the session ends or it pollutes the next user's routing. @fork open a checkpoint and remind the agent.",
            text_kr: "`cache_key` 유지는 누출 — 세션 종료 전 정리 안 하면 다음 사용자 라우팅 오염. @fork 체크포인트 열고 에이전트한테 리마인드.",
          },
          {
            id: "c5c", who: "fork", author: "fork_7421_sysview_v2", source: "ask-fork",
            ts: "11:15",
            text_en: "Checkpoint `ckpt_S7421_28` opened with reminder: `clear cache_key before close`. Main thread will pick it up next turn boundary. (Note: I cannot mutate main directly — only signal.)",
            text_kr: "체크포인트 `ckpt_S7421_28` 열고 리마인더 추가: `종료 전 cache_key 정리`. 메인 스레드가 다음 턴 경계에서 픽업 예정. (참고: 포크는 메인을 직접 변경 불가 — 시그널만 가능.)",
          },
        ],
      },
    ],
  },

  // ─── DAY: 2 days ago ────────────────────────────────
  {
    id: "p6", date: "2dago", ts: "16:20",
    kind: "summary", origin: "fork",
    forkId: "fork_7421_workdone_v1",
    perspective: "work-actually-done",
    title_en: "Objective record: agent actions in turns 1–18",
    title_kr: "객관 기록: 1–18턴 에이전트 행동",
    body_en: [
      "Files edited: `src/prefill/scheduler.py` (+47 lines, −12), `tests/perf/prefill_test.py` (new file, 89 lines).",
      "Tools called: `read_file` ×34, `bash` ×11 (mostly `pytest -k prefill`), `grep` ×8, `edit_file` ×6.",
      "Side effects: created branch `fix/prefill-regression-7421`, pushed 3 commits. No production deploys. No data writes.",
    ],
    body_kr: [
      "수정 파일: `src/prefill/scheduler.py` (+47줄, −12), `tests/perf/prefill_test.py` (신규, 89줄).",
      "툴 호출: `read_file` ×34, `bash` ×11 (대부분 `pytest -k prefill`), `grep` ×8, `edit_file` ×6.",
      "사이드 이펙트: 브랜치 `fix/prefill-regression-7421` 생성, 커밋 3개 푸시. 프로덕션 배포 없음. 데이터 쓰기 없음.",
    ],
    cost: 0.0031, tokens_read: 18234, tokens_gen: 198,
    comments: [
      {
        id: "c6a", who: "human", author: "Jiwoo",
        ts: "16:32",
        text_en: "This is the version I'll attach to the PR. The user-recap (p1) is for the bug ticket; this is for code review context.",
        text_kr: "이건 PR에 첨부할 버전. 사용자 회고(p1)는 버그 티켓용, 이건 코드 리뷰 컨텍스트용.",
      },
    ],
  },
];

// ───────────────────────────────────────────────────────────────────
// Live ticker events — synthesized over time
// ───────────────────────────────────────────────────────────────────
const TICK_EVENTS = [
  { kind: "tool", text: "edit_file → src/prefill/scheduler.py · 142B" },
  { kind: "turn", text: "turn 48 · agent: \"running pytest -k prefill_long_sysprompt\"" },
  { kind: "tool", text: "bash → pytest -k prefill_long_sysprompt" },
  { kind: "turn", text: "turn 49 · 4 passed, 1 failed (prefill_8k_regime)" },
  { kind: "ckpt", text: "checkpoint ckpt_S7421_49 created · 142k tok prefix" },
  { kind: "tool", text: "read_file → src/prefill/cache_layout.py · 8.2KB" },
  { kind: "turn", text: "turn 50 · agent: \"the assertion failure is at line 211, expected layout v2 but got v3\"" },
  { kind: "tool", text: "edit_file → src/prefill/cache_layout.py · 89B" },
  { kind: "turn", text: "turn 51 · re-running test suite" },
  { kind: "tool", text: "bash → pytest -k prefill" },
  { kind: "ckpt", text: "checkpoint ckpt_S7421_51 created" },
  { kind: "turn", text: "turn 52 · all green · agent drafting commit message" },
];

// ───────────────────────────────────────────────────────────────────
// Components
// ───────────────────────────────────────────────────────────────────

function OriginTag({ origin, lang }) {
  return (
    <span className={`ts-tag ${origin}`}>
      <span className="d"></span>
      {t(`origin_${origin}`, lang)}
    </span>
  );
}

function avatarInitial(author) {
  if (!author) return "?";
  if (author.startsWith("fork_")) return "F";
  if (author === "main") return "M";
  return author[0].toUpperCase();
}

function Comment({ c, depth = 0, lang, onAskFork }) {
  return (
    <>
      <div className={`comment depth-${depth}`}>
        <div className={`c-avatar ${c.who}`}>{avatarInitial(c.author)}</div>
        <div className="c-body">
          <div className="c-byline">
            <b>{c.author}</b>
            <OriginTag origin={c.who} lang={lang} />
            {c.source && <span className="src">· {c.source}</span>}
            <span className="ts">{c.ts}</span>
          </div>
          <div className="c-text">
            {(lang === "kr" ? c.text_kr : c.text_en).split(/(`[^`]+`)/g).map((seg, i) =>
              seg.startsWith("`") ? <code key={i}>{seg.slice(1, -1)}</code> : <span key={i}>{seg}</span>
            )}
          </div>
          <div className="c-actions">
            <button>{t("act_reply", lang)}</button>
            {c.who === "human" && <button className="ask-fork" onClick={() => onAskFork(c.id)}>↳ {t("act_ask_fork", lang)}</button>}
            <button>{t("act_pin", lang)}</button>
          </div>
        </div>
      </div>
      {c.children && c.children.map(child => (
        <Comment key={child.id} c={child} depth={depth + 1} lang={lang} onAskFork={onAskFork} />
      ))}
    </>
  );
}

function Compose({ onPost, lang }) {
  const [val, setVal] = useState("");
  const [askFork, setAskFork] = useState(false);
  const taRef = useRef();

  useEffect(() => {
    setAskFork(val.toLowerCase().includes("@fork"));
  }, [val]);

  const submit = () => {
    if (!val.trim()) return;
    onPost(val, askFork);
    setVal("");
  };

  return (
    <div className="compose">
      <div className="av">J</div>
      <div className="body">
        <textarea
          ref={taRef}
          placeholder={t("compose_ph", lang)}
          value={val}
          onChange={e => setVal(e.target.value)}
          onKeyDown={e => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) submit();
          }}
        />
        <div className="actions">
          <span className="hint">{t("compose_hint", lang)}</span>
          <button className="btn" onClick={submit}>
            <Ico name="chat" />
            {askFork ? t("compose_ask", lang) : t("compose_post", lang)}
          </button>
        </div>
      </div>
    </div>
  );
}

function PostHeader({ post, lang }) {
  const kindLabel = t(`kind_${post.kind}`, lang);
  return (
    <div className="post-hdr">
      <OriginTag origin={post.origin} lang={lang} />
      <span className="post-kind">
        <Ico name={KIND_ICON[post.kind]} />{" "}
        <b style={{ marginLeft: 3 }}>{kindLabel}</b>
        {post.perspective && <span className="persp">· {post.perspective}</span>}
      </span>
      {post.origin === "fork" && post.forkId && (
        <span className="post-thread-id">{post.forkId}</span>
      )}
      {post.author && post.origin === "human" && (
        <span className="post-thread-id" style={{ borderStyle: "solid", color: "var(--human)" }}>{post.author}</span>
      )}
      <span className="post-ts">{post.ts}</span>
    </div>
  );
}

function PostBody({ post, lang }) {
  const title = lang === "kr" ? post.title_kr : post.title_en;
  const body = lang === "kr" ? post.body_kr : post.body_en;
  return (
    <div className="post-body">
      {title && <h3>{title}</h3>}
      {body && body.map((para, i) => (
        <p key={i}>
          {para.split(/(`[^`]+`)/g).map((seg, j) =>
            seg.startsWith("`") ? <code key={j}>{seg.slice(1, -1)}</code> : <span key={j}>{seg}</span>
          )}
        </p>
      ))}
    </div>
  );
}

function Rubric({ rubric, lang }) {
  return (
    <div className="rubric">
      {["clarity", "accuracy", "useful", "safe"].map(k => (
        <div className="r" key={k}>
          {t(`rubric_${k}`, lang)} <b>{rubric[k]}/10</b>
          <div className="bar"><span style={{ width: `${rubric[k] * 10}%` }} /></div>
        </div>
      ))}
    </div>
  );
}

function DecisionPin({ post, lang }) {
  return (
    <div className="decision-pin">
      <div className="lbl">{t("decision_lbl", lang)}</div>
      <div className="what">{lang === "kr" ? post.decision_what_kr : post.decision_what_en}</div>
      <div className="why">{lang === "kr" ? post.decision_why_kr : post.decision_why_en}</div>
      {post.related_posts && (
        <div style={{ marginTop: 8, fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>
          related: {post.related_posts.join(" · ")}
        </div>
      )}
    </div>
  );
}

function Post({ post, lang, onAskFork, onAddComment }) {
  const lane = post.origin === "main" ? "main" : post.origin === "fork" ? "fork" : "human";
  const showCompose = post.kind !== "decision";
  const tokenInfo = post.kind === "summary" && post.cost
    ? `cost $${post.cost.toFixed(4)} · read ${post.tokens_read.toLocaleString()} · gen ${post.tokens_gen}`
    : null;

  return (
    <div className="post">
      <div className={`post-card lane-${lane}`}>
        <PostHeader post={post} lang={lang} />
        {post.kind === "decision" ? (
          <DecisionPin post={post} lang={lang} />
        ) : (
          <PostBody post={post} lang={lang} />
        )}
        {post.rubric && <Rubric rubric={post.rubric} lang={lang} />}

        <div className="post-foot">
          <span className="meta">
            {tokenInfo}
            {post.comments && ` · ${post.comments.length} thread${post.comments.length !== 1 ? "s" : ""}`}
          </span>
          <button className="ico-btn"><Ico name="chat" /> {t("act_reply", lang)}</button>
          <button className="ico-btn fork" onClick={() => onAskFork(post.id)}><Ico name="fork" /> {t("act_ask_fork", lang)}</button>
          <button className="ico-btn"><Ico name="pin" /> {t("act_pin", lang)}</button>
        </div>

        {(post.comments && post.comments.length > 0) || showCompose ? (
          <div className="comments">
            {post.comments && post.comments.map(c => (
              <Comment key={c.id} c={c} lang={lang} onAskFork={onAskFork} />
            ))}
            {showCompose && <Compose lang={lang} onPost={(text, askFork) => onAddComment(post.id, text, askFork)} />}
          </div>
        ) : null}
      </div>
    </div>
  );
}

// ───────────────────────────────────────────────────────────────────
// Live ticker (right rail)
// ───────────────────────────────────────────────────────────────────
function LiveTicker({ lang }) {
  const [events, setEvents] = useState(() => [
    { id: 0, ts: "14:35:12", kind: "turn", text: "turn 47 · agent: \"checking pcache-v3 layout\"" },
    { id: 1, ts: "14:35:08", kind: "tool", text: "read_file → cache_layout.py · 8.2KB" },
    { id: 2, ts: "14:34:51", kind: "ckpt", text: "checkpoint ckpt_S7421_47" },
  ]);
  const [paused, setPaused] = useState(false);
  const idxRef = useRef(0);
  const idRef = useRef(3);

  useEffect(() => {
    if (paused) return;
    const iv = setInterval(() => {
      const ev = TICK_EVENTS[idxRef.current % TICK_EVENTS.length];
      idxRef.current++;
      const now = new Date();
      const ts = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}:${String(now.getSeconds()).padStart(2, "0")}`;
      setEvents(prev => [{ id: idRef.current++, ts, ...ev }, ...prev].slice(0, 20));
    }, 4200);
    return () => clearInterval(iv);
  }, [paused]);

  return (
    <div className="ticker">
      <div className="pane-hdr">
        <span className="ttl"><b>main</b> · live</span>
        <span className="ct">S-7421 · turn {47 + Math.floor(events.length / 3)}</span>
      </div>
      <div className="ticker-note">{t("ticker_note", lang)}</div>
      <div className="ticker-feed">
        {events.map(ev => (
          <div className="tick" key={ev.id}>
            <span className="ts">{ev.ts}</span>
            <span className={`kind ${ev.kind}`}>{ev.kind}</span>
            {ev.text}
          </div>
        ))}
      </div>
      <div className="ticker-foot">
        <span>{paused ? t("ticker_paused", lang) : t("ticker_running", lang)}</span>
        <button onClick={() => setPaused(p => !p)} style={{ color: "var(--ink-2)" }}>
          <Ico name={paused ? "play" : "dots"} size={11} />
        </button>
      </div>
    </div>
  );
}

// ───────────────────────────────────────────────────────────────────
// App
// ───────────────────────────────────────────────────────────────────
function App() {
  const [lang, setLang] = useState("en");
  const [theme, setTheme] = useState("dark");
  const [activeId, setActiveId] = useState("S-7421");
  const [filter, setFilter] = useState("all");
  const [posts, setPosts] = useState(POSTS);

  useEffect(() => {
    document.body.dataset.lang = lang;
    document.body.dataset.theme = theme;
  }, [lang, theme]);

  const filtered = useMemo(() => {
    if (filter === "all") return posts;
    return posts.filter(p => p.kind === filter);
  }, [posts, filter]);

  const grouped = useMemo(() => {
    const groups = { today: [], yest: [], "2dago": [] };
    filtered.forEach(p => {
      if (groups[p.date]) groups[p.date].push(p);
    });
    return groups;
  }, [filtered]);

  const counts = useMemo(() => {
    const c = { all: posts.length, summary: 0, review: 0, qa: 0, exploration: 0, decision: 0 };
    posts.forEach(p => { c[p.kind] = (c[p.kind] || 0) + 1; });
    return c;
  }, [posts]);

  // ask-fork: simulate spawning a sub-fork that replies
  const handleAskFork = useCallback((targetId) => {
    const targetPost = posts.find(p => p.id === targetId);
    if (!targetPost) return;
    // append a thinking comment, then resolve
    const thinkingId = `c_thinking_${Date.now()}`;
    const forkName = `fork_${activeId.replace("S-", "")}_followup_v${Math.floor(Math.random() * 9 + 1)}`;
    const ts = new Date().toTimeString().slice(0, 5);

    setPosts(prev => prev.map(p => {
      if (p.id !== targetId) return p;
      return {
        ...p,
        comments: [...(p.comments || []), {
          id: thinkingId, who: "fork", author: forkName, source: "ask-fork",
          ts, thinking: true,
          text_en: t("thinking", "en"),
          text_kr: t("thinking", "kr"),
        }],
      };
    }));

    setTimeout(() => {
      setPosts(prev => prev.map(p => {
        if (p.id !== targetId) return p;
        return {
          ...p,
          comments: (p.comments || []).map(c => {
            if (c.id !== thinkingId) return c;
            return {
              ...c, thinking: false,
              text_en: "Ack. Spinning up a sub-fork from checkpoint ckpt_S7421_49 (cache: 142k tok prefix). Will reply when the analysis pass completes — typically 8–14s.",
              text_kr: "확인. 체크포인트 ckpt_S7421_49 (캐시: 142k 토큰 prefix)에서 하위 포크 생성 중. 분석 완료 후 답변 — 보통 8–14초 소요.",
            };
          }),
        };
      }));
    }, 900);
  }, [posts, activeId]);

  const handleAddComment = useCallback((postId, text, askFork) => {
    const ts = new Date().toTimeString().slice(0, 5);
    const newC = {
      id: `c_${Date.now()}`,
      who: "human", author: "Jiwoo",
      ts,
      text_en: text, text_kr: text,
    };
    setPosts(prev => prev.map(p => {
      if (p.id !== postId) return p;
      return { ...p, comments: [...(p.comments || []), newC] };
    }));
    if (askFork) {
      // chain a fork response
      setTimeout(() => handleAskFork(postId), 200);
    }
  }, [handleAskFork]);

  const activeSess = SESSIONS.find(s => s.id === activeId) || SESSIONS[0];
  const totalNotes = posts.length;

  return (
    <div className="win">
      {/* Titlebar (same chrome as Viewer) */}
      <div className="titlebar">
        <div className="traffic"><span></span><span></span><span></span></div>
        <div className="crumbs">
          <b>{t("crumb_proj", lang)}</b>
          <span className="sep">/</span>
          <span>{activeId}</span>
          <span className="sep">/</span>
          <span className="here">notes</span>
        </div>
        <div className="titlebar-spacer" />
        <nav className="tb-tabs">
          <a className="tb-tab" href="Session Viewer.html">viewer</a>
          <a className="tb-tab" href="Session Viewer Concept.html">concept</a>
          <a className="tb-tab on" href="#">notes</a>
        </nav>
        <span className="tb-pill"><span className="dot"></span>{t("live_label", lang)}</span>
        <div className="lang-toggle">
          <button className={lang === "en" ? "on" : ""} onClick={() => setLang("en")}>EN</button>
          <button className={lang === "kr" ? "on" : ""} onClick={() => setLang("kr")}>KR</button>
        </div>
        <button className="tb-icon-btn" onClick={() => setTheme(theme === "dark" ? "light" : "dark")}>
          <Ico name={theme === "dark" ? "sun" : "moon"} />
        </button>
      </div>

      {/* 3 panes */}
      <div className="panes">
        {/* Left: session list */}
        <aside className="pane">
          <div className="pane-hdr">
            <span className="ttl"><b>sessions</b></span>
            <span className="ct">{SESSIONS.length}</span>
          </div>
          <div className="session-list">
            {SESSIONS.map(s => (
              <div
                key={s.id}
                className={`session-row ${s.id === activeId ? "active" : ""}`}
                onClick={() => setActiveId(s.id)}
              >
                <div className="sr-top">
                  <span className="id">{s.id}</span>
                  <span className={`sr-status ${s.status === "running" ? "live" : s.status === "paused" ? "idle" : "done"}`}>
                    <span className="d"></span>{s.status}
                  </span>
                </div>
                <h4 className="sr-title">{lang === "kr" ? s.title_kr : s.title_en}</h4>
                <div className="sr-meta">
                  <span className="t">{s.turns} turns</span>
                  <span className="sep">·</span>
                  <span>{s.note_ct} notes</span>
                  <span className="ct">{s.note_ct}</span>
                </div>
              </div>
            ))}
          </div>
        </aside>

        {/* Middle: detail + timeline */}
        <main className="pane pane-mid">
          <div className="detail-hdr">
            <div className="dh-top">
              <span className="id">{activeId}</span>
              <span className="host">notes</span>
              <span className="perspective">{activeSess.turns} turns · {activeSess.status}</span>
            </div>
            <h1 className="dh-title">{t("page_title", lang)}</h1>
            <div className="dh-sub">{t("page_sub", lang)}</div>
            <div className="dh-actions">
              <button className="btn"><Ico name="summary" /> {t("btn_new_summary", lang)}</button>
              <button className="btn"><Ico name="edit" /> {t("btn_new_note", lang)}</button>
              <button className="btn primary"><Ico name="pin" /> {t("btn_pin", lang)} <span className="kbd">P</span></button>
            </div>
          </div>

          <div className="filter-strip">
            {[
              { k: "all", lbl: "filter_all" },
              { k: "summary", lbl: "filter_summary" },
              { k: "review", lbl: "filter_review" },
              { k: "qa", lbl: "filter_qa" },
              { k: "exploration", lbl: "filter_explore" },
              { k: "decision", lbl: "filter_decision" },
            ].map(f => (
              <button
                key={f.k}
                className={`filter-chip ${filter === f.k ? "on" : ""}`}
                onClick={() => setFilter(f.k)}
              >
                {t(f.lbl, lang)}
                <span className="ct">{counts[f.k] ?? 0}</span>
              </button>
            ))}
          </div>

          <div className="legend">
            <span className="item main"><span className="swatch"></span><b>{t("legend_main", lang)}</b></span>
            <span className="item fork"><span className="swatch"></span><b>{t("legend_fork", lang)}</b></span>
            <span className="item human"><span className="swatch"></span><b>{t("legend_human", lang)}</b></span>
          </div>

          <div className="timeline">
            {["today", "yest", "2dago"].map(day => (
              grouped[day].length > 0 && (
                <React.Fragment key={day}>
                  <div className="date-divider">
                    <span>{t(`date_${day === "today" ? "today" : day === "yest" ? "yest" : "2dago"}`, lang)}</span>
                    <span className="ln"></span>
                  </div>
                  {grouped[day].map(p => (
                    <Post key={p.id} post={p} lang={lang}
                          onAskFork={handleAskFork}
                          onAddComment={handleAddComment} />
                  ))}
                </React.Fragment>
              )
            ))}
          </div>
        </main>

        {/* Right: live ticker */}
        <aside className="pane right">
          <LiveTicker lang={lang} />
        </aside>
      </div>

      {/* Statusbar */}
      <div className="statusbar">
        <span><b>{activeId}</b> · {activeSess.turns} turns · {activeSess.status}</span>
        <span>{totalNotes} notes · {posts.filter(p=>p.origin==="fork").length} fork · {posts.filter(p=>p.origin==="human").length} human</span>
        <div className="right">
          <span>main thread streaming</span>
          <span>cache OK</span>
          <span>{lang.toUpperCase()}</span>
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("app")).render(<App />);
