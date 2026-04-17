# Reduces an array of hourly snapshot JSON documents (slurped via `jq -s`)
# into a single metrics document used by the dashboard, status README,
# highlights markdown, and the per-failing-suite issues.
#
# Inputs:
#   - argument $now: ISO 8601 timestamp used as "now" for window math.
#   - input: array of snapshot objects, each with shape
#     { generated_at: ISO8601, suites: [ { workflow,label,conclusion,url } ] }
#
# Output: { generated_at, suites: [...], highlights: { ... } }
#
# Tested by .github/workflows/_self-test.yml against tests/fixtures/snapshots/*.

def parse_ts(s): s | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
def now_epoch: $now | parse_ts(.);
def day_str(e): (e | todate)[0:10];

# Uptime as percentage rounded to one decimal place. Null when no data.
def uptime(arr):
  (arr | length) as $n
  | if $n == 0 then null
    else ((arr | map(select(.conclusion=="success")) | length) * 1000 / $n | floor / 10)
    end;

# Flake count = success<->failure transitions in window.
def flakes(arr):
  if (arr | length) < 2 then 0
  else [range(1; arr|length) | select(arr[.].conclusion != arr[.-1].conclusion)] | length
  end;

([ .[] as $snap | $snap.suites[] | select(.workflow != "_scheduler.yml")
   | { workflow, label, conclusion, url, ts: $snap.generated_at } ]
| group_by(.workflow)
| map(
    sort_by(.ts) as $h
    | ($h[-1].label) as $label
    | ($h[-1]) as $latest
    | ($h[-2] // null) as $prev
    | ($h | map(select(.conclusion == "success" or .conclusion == "failure"))) as $hd
    | ($hd | map(select(.conclusion == "success")) | length) as $succ
    | ($hd | map(select(.conclusion == "failure")) | length) as $fail
    | ($hd | length) as $tot
    | (now_epoch - 86400)  as $t24
    | (now_epoch - 604800) as $t7d
    | (now_epoch - 2592000) as $t30d
    | ($hd | map(select((.ts | parse_ts(.)) >= $t24)))  as $w24
    | ($hd | map(select((.ts | parse_ts(.)) >= $t7d)))  as $w7d
    | ($hd | map(select((.ts | parse_ts(.)) >= $t30d))) as $w30d
    # Per-day uptime series for the last 30 UTC days, oldest first.
    # Days with zero runs emit uptime=null, runs=0 — never fabricate values.
    | ((now_epoch / 86400 | floor) * 86400) as $today_start
    | ([range(0; 30)] | map($today_start - (29 - .) * 86400)) as $day_starts
    | ($hd | map(. + {day: day_str(.ts | parse_ts(.))})) as $hd_with_day
    | ($day_starts | map(
        day_str(.) as $d
        | ($hd_with_day | map(select(.day == $d))) as $r
        | { day: $d, runs: ($r | length), uptime: uptime($r) }
      )) as $trend30
    # Current streak: trailing run of identical conclusions.
    | (reduce ($hd | reverse[]) as $e ({c: $latest.conclusion, n: 0, done: false};
        if .done then . elif $e.conclusion == .c then .n += 1 else .done = true end))
      as $streak
    # MTTR over 7d: avg gap between a failure and the next success (seconds).
    | (reduce range(0; ($w7d|length)) as $i (
        {acc: 0, count: 0, last_fail: null};
        ($w7d[$i]) as $e
        | if $e.conclusion == "failure" and (.last_fail == null) then .last_fail = ($e.ts | parse_ts(.))
          elif $e.conclusion == "success" and (.last_fail != null) then
            .acc += (($e.ts | parse_ts(.)) - .last_fail) | .count += 1 | .last_fail = null
          else . end))
      as $mttr
    | {
        workflow: $latest.workflow,
        label: $label,
        latest: $latest,
        prev: $prev,
        flipped: ($prev != null and $prev.conclusion != $latest.conclusion),
        total_seen: $tot,
        success: $succ,
        failure: $fail,
        uptime_24h: uptime($w24),
        uptime_7d:  uptime($w7d),
        uptime_30d: uptime($w30d),
        streak_count: $streak.n,
        streak_state: $latest.conclusion,
        flakes_7d: flakes($w7d),
        mttr_7d_seconds: (if $mttr.count > 0 then ($mttr.acc / $mttr.count | floor) else null end),
        trend_30d: $trend30
      }
  )) as $suites
| {
    generated_at: $now,
    suites: $suites,
    highlights: {
      new_failures: ([$suites[] | select(.flipped and .latest.conclusion=="failure")
                     | {workflow:.workflow,label:.label,url:.latest.url}]),
      recoveries:   ([$suites[] | select(.flipped and .latest.conclusion=="success")
                     | {workflow:.workflow,label:.label,url:.latest.url}]),
      long_red:     ([$suites[] | select(.streak_state=="failure" and .streak_count>=3)
                     | {workflow:.workflow,label:.label,hours:.streak_count,url:.latest.url}]
                     | sort_by(-.hours)),
      flakiest:     ([$suites[] | select(.flakes_7d>0)
                     | {workflow:.workflow,label:.label,flakes:.flakes_7d}]
                     | sort_by(-.flakes) | .[0:5]),
      low_uptime:   ([$suites[] | select(.uptime_24h != null and .uptime_24h < 95)
                     | {workflow:.workflow,label:.label,uptime_24h:.uptime_24h}]
                     | sort_by(.uptime_24h) | .[0:5])
    }
  }
