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

rpc() { # rpc <json> [extra curl args...]
  local body="$1"; shift
  curl -sS --max-time 90 -X POST "$URL" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' ${SESSION:+-H "Mcp-Session-Id: $SESSION"} "$@" -d "$body"
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

check "get_test_plan sees the plan" "Smoke test plan" "$(rpc "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"get_test_plan\",\"arguments\":{\"plan_id\":\"$PLAN_ID\",\"detail\":\"full\"}}}")"
check "list_test_plans finds it by keyword" "$PLAN_ID" "$(rpc '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"list_test_plans","arguments":{"query":"smoke"}}}')"
check "wait_for_test_plan times out cleanly" 'timed_out' "$(rpc "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"wait_for_test_plan\",\"arguments\":{\"plan_id\":\"$PLAN_ID\",\"timeout_seconds\":1}}}")"
check "complete without force is refused" 'force=true' "$(rpc "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"complete_test_plan\",\"arguments\":{\"plan_id\":\"$PLAN_ID\"}}}")"
check "complete with force succeeds" 'deleted from the user' "$(rpc "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"complete_test_plan\",\"arguments\":{\"plan_id\":\"$PLAN_ID\",\"force\":true}}}")"
check "plan is gone afterwards" 'No active test plan' "$(rpc "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"get_test_plan\",\"arguments\":{\"plan_id\":\"$PLAN_ID\"}}}")"

echo "Security and HTTP behavior"
check "browser Origin -> 403" "403" "$(status -X POST "$URL" -H 'Origin: https://evil.example' -d '{}')"
check "wrong Host -> 403" "403" "$(status -X POST "$URL" -H 'Host: evil.example' -d '{}')"
check "GET -> 405" "405" "$(status "$URL")"
check "unknown path -> 404" "404" "$(status "http://127.0.0.1:${PORT}/nope")"
check "malformed JSON -> 400" "400" "$(status -X POST "$URL" -d '{nope')"
check "chunked body -> 501" "501" "$(status -X POST "$URL" -H 'Transfer-Encoding: chunked' -d '{}')"
BIG="$(python3 -c "import json; print(json.dumps({'jsonrpc':'2.0','id':10,'method':'ping','pad':'x'*200000}))")"
check "200 KB body (Expect: 100-continue) accepted" "200" "$(status -X POST "$URL" -H 'Content-Type: application/json' -H 'Expect: 100-continue' -d "$BIG")"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  printf '\033[32mAll checks passed.\033[0m\n'
else
  printf '\033[31m%d check(s) failed.\033[0m\n' "$FAILURES"
  exit 1
fi
