#!/usr/bin/env bash
#
# Wire-level smoke test for a running ManualTestPlan app.
#
# Usage: Scripts/smoke-test.sh [port]      (default port: 47821)
#
# Walks the MCP lifecycle over real HTTP with curl: initialize -> tools/list -> create_test_plan ->
# get_test_plan -> list_test_plans -> security checks -> complete_test_plan. The plan it creates is
# force-completed at the end, which also verifies deletion.
#
# The app must be running. This can't live in the unit tests because the sandboxed test host has no
# outbound-network entitlement.

set -euo pipefail

PORT="${1:-47821}"
URL="http://127.0.0.1:${PORT}/mcp"
FAILURES=0

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

check() { # check <description> <expected substring> <actual>
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1 (expected to contain '$2', got: ${3:0:300})"; fi
}

SESSION=""

rpc() { # rpc <json> [extra curl args...]
  local body="$1"; shift
  local args=(-sS --max-time 90 -X POST "$URL" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
  if [[ -n "$SESSION" ]]; then args+=(-H "Mcp-Session-Id: $SESSION"); fi
  curl "${args[@]}" "$@" -d "$body"
}

# call <id> <tool> <arguments-json>: a tools/call request. Bodies are built with single-quoted printf
# templates because macOS's bash 3.2 mangles backslash-escaped quotes inside "$(...)".
call() {
  rpc "$(printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2" "$3")"
}

status() { # status <curl args...> -> HTTP status code only
  curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$@"
}

echo "Smoke testing ${URL}"

if ! curl -sS --max-time 3 -o /dev/null "$URL" 2>/dev/null; then
  echo "Nothing is listening on port ${PORT}. Launch ManualTestPlan first." >&2
  exit 2
fi

echo "Protocol"
HEADERS="$(mktemp)"; trap 'rm -f "$HEADERS"' EXIT
INIT="$(rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1"}}}' -D "$HEADERS")"
check "initialize returns serverInfo" '"name":"ManualTestPlan"' "$INIT"
SESSION="$(awk 'tolower($1)=="mcp-session-id:" {print $2}' "$HEADERS" | tr -d '\r')"
[[ -n "$SESSION" ]] && pass "session id issued" || fail "no Mcp-Session-Id header"

check "initialized notification -> 202" "202" "$(status -X POST "$URL" -H 'Content-Type: application/json' -H "Mcp-Session-Id: $SESSION" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}')"
check "tools/list names create_test_plan" 'create_test_plan' "$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"

echo "Plan lifecycle"
CREATE="$(rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_test_plan","arguments":{"title":"Smoke test plan","summary":"Created by Scripts/smoke-test.sh","cases":[{"title":"Only case","steps":[{"instruction":"Do nothing","expected":"Nothing happens"}]}]}}}')"
PLAN_ID="$(printf '%s' "$CREATE" | grep -o 'tp_[a-z0-9]*' | head -1)"
[[ -n "$PLAN_ID" ]] && pass "create_test_plan returned $PLAN_ID" || { fail "no plan_id in: $CREATE"; exit 1; }

GET_ARGS="$(printf '{"plan_id":"%s","detail":"full"}' "$PLAN_ID")"
PLAN_ARGS="$(printf '{"plan_id":"%s"}' "$PLAN_ID")"
WAIT_ARGS="$(printf '{"plan_id":"%s","timeout_seconds":1}' "$PLAN_ID")"
FORCE_ARGS="$(printf '{"plan_id":"%s","force":true}' "$PLAN_ID")"

OUT="$(call 4 get_test_plan "$GET_ARGS")";                  check "get_test_plan sees the plan" "Smoke test plan" "$OUT"
OUT="$(call 5 list_test_plans '{"query":"smoke"}')";       check "list_test_plans finds it by keyword" "$PLAN_ID" "$OUT"
OUT="$(call 6 wait_for_test_plan "$WAIT_ARGS")";            check "wait_for_test_plan times out cleanly" "timed_out" "$OUT"
OUT="$(call 7 complete_test_plan "$PLAN_ARGS")";            check "complete without force is refused" "force=true" "$OUT"
OUT="$(call 8 complete_test_plan "$FORCE_ARGS")";           check "complete with force succeeds" "deleted from the user" "$OUT"
OUT="$(call 9 get_test_plan "$PLAN_ARGS")";                 check "plan is gone afterwards" "No active test plan" "$OUT"

echo "Security and HTTP behavior"
check "browser Origin -> 403" "403" "$(status -X POST "$URL" -H 'Origin: https://evil.example' -d '{}')"
check "wrong Host -> 403" "403" "$(status -X POST "$URL" -H 'Host: evil.example' -d '{}')"
check "GET -> 405" "405" "$(status "$URL")"
check "unknown path -> 404" "404" "$(status "http://127.0.0.1:${PORT}/nope")"
check "malformed JSON -> 400" "400" "$(status -X POST "$URL" -d '{nope')"
check "chunked body -> 501" "501" "$(status -X POST "$URL" -H 'Transfer-Encoding: chunked' -d '{}')"
BIG="$(python3 -c "import json; print(json.dumps({'jsonrpc':'2.0','id':10,'method':'ping','pad':'x'*200000}))")"
check "200 KB body (Expect: 100-continue) accepted" "200" "$(status -X POST "$URL" -H 'Content-Type: application/json' -H 'Expect: 100-continue' -d "$BIG")"

# Regression guard: NetworkListener's newConnectionLimit counts every connection ever accepted, so a cap
# silently kills the server after that many requests. Every request here opens a new connection.
BAD=0
for i in $(seq 1 100); do
  [[ "$(status -X POST "$URL" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"ping"}')" == "200" ]] || BAD=$((BAD + 1))
done
if [[ "$BAD" -eq 0 ]]; then pass "100 consecutive connections all served"; else fail "$BAD of 100 consecutive connections failed"; fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  printf '\033[32mAll checks passed.\033[0m\n'
else
  printf '\033[31m%d check(s) failed.\033[0m\n' "$FAILURES"
  exit 1
fi
