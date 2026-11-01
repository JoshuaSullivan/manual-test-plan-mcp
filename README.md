# ManualTestPlan

A macOS menu bar app that lets an AI agent hand you a checklist of manual checks, and read your verdicts back. For the things an agent can't verify itself: gestures, drag and drop, visual polish, permission prompts.

The agent creates a plan over MCP; a window opens; you mark each step **Passed**, **Failed**, or **Blocked**, add notes, and attach any file (screenshots, logs, crash reports). The agent reads the results by plan ID, then completes the plan, which deletes it and its attachments.

## Connect an agent

Launch the app, then register it with Claude Code:

```sh
claude mcp add --transport http manualtestplan http://127.0.0.1:47821/mcp
```

The port is configurable in Settings; the menu bar item has a "Copy MCP Setup Command" entry that always matches it. Any MCP client that speaks Streamable HTTP works.

## Tools

| Tool | Purpose |
|---|---|
| `create_test_plan` | Create a plan of cases and steps; opens its window |
| `get_test_plan` | Status and results (`summary` shows only failed/blocked steps) |
| `wait_for_test_plan` | Block until you record a verdict, or time out |
| `get_step_evidence` | Your attachments: images as images, text inline, other files by path |
| `list_test_plans` | Find plans by keyword |
| `add_to_test_plan` | Append cases or steps |
| `revise_step` | Fix a step's wording and reset it (for `blocked` steps) |
| `complete_test_plan` | Return the final report, then delete the plan and its files |

## Security

The server listens on `127.0.0.1` only and rejects requests with a browser `Origin` header or an unexpected `Host`, which blocks web pages from reaching it. Any other process running as you can still call it.

## Development

Open `ManualTestPlan/ManualTestPlan.xcodeproj` (Xcode 26+, macOS 26+). Unit tests cover everything except the sandboxed network client side, which `Scripts/smoke-test.sh` exercises against the running app:

```sh
Scripts/smoke-test.sh        # app must be running; optional port argument
```
