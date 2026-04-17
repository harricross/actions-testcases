# Renders a metrics document (output of metrics.jq) as a markdown
# highlights document used in: status/highlights.md, the status
# branch's README, and aggregator $GITHUB_STEP_SUMMARY.

def fmt_pct(p): if p == null then "n/a" else "\(p)%" end;
def fmt_dur(s):
  if s == null then "n/a"
  else (s/60|floor) as $m
    | if $m < 60 then "\($m)m"
      elif $m < 1440 then "\($m/60|floor)h"
      else "\($m/1440|floor)d" end
  end;

"# Highlights — \(.generated_at)",
"",
(if (.highlights.new_failures|length) > 0 then
  "## 🆕 New failures this hour",
  "",
  (.highlights.new_failures[] | "- ❌ **\(.label)** — [run](\(.url))"),
  ""
 else empty end),
(if (.highlights.recoveries|length) > 0 then
  "## ✅ Recoveries this hour",
  "",
  (.highlights.recoveries[] | "- 🟢 **\(.label)** — [run](\(.url))"),
  ""
 else empty end),
(if (.highlights.long_red|length) > 0 then
  "## 🔥 Currently failing for ≥ 3 hours",
  "",
  (.highlights.long_red[] | "- **\(.label)** — \(.hours)h — [run](\(.url))"),
  ""
 else empty end),
(if (.highlights.flakiest|length) > 0 then
  "## 🦋 Flakiest (last 7d)",
  "",
  (.highlights.flakiest[] | "- **\(.label)** — \(.flakes) transitions"),
  ""
 else empty end),
(if (.highlights.low_uptime|length) > 0 then
  "## 📉 Lowest uptime (last 24h)",
  "",
  (.highlights.low_uptime[] | "- **\(.label)** — \(fmt_pct(.uptime_24h))"),
  ""
 else empty end),
"## Per-suite snapshot",
"",
"| Suite | Latest | Streak | Uptime 24h | Uptime 7d | Flakes 7d | MTTR 7d |",
"|---|---|---|---|---|---|---|",
(.suites[] |
  ((.latest.conclusion // "—") as $c |
   (if $c == "success" then "✅"
    elif $c == "failure" then "❌"
    elif $c == "cancelled" then "🟡"
    else "⚪" end) as $icon |
   "| \(.label) | \($icon) \($c) | \(.streak_count) \(.streak_state) | \(fmt_pct(.uptime_24h)) | \(fmt_pct(.uptime_7d)) | \(.flakes_7d) | \(fmt_dur(.mttr_7d_seconds)) |"
  ))
