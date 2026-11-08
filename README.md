# ManualTestPlan

A macOS menu bar app that lets an AI agent hand you a checklist of manual checks and read your verdicts back.

Agents can't verify everything: gestures, drag and drop, visual polish, animations, permission prompts, hardware. Normally they dump a to-do list into the chat and you relay the results by hand. With ManualTestPlan the agent creates a structured plan over [MCP](https://modelcontextprotocol.io), a window opens on your Mac, and you mark each step **Passed**, **Failed**, or **Blocked**, add notes, and attach evidence. The agent reads the results by plan ID, fixes whatever you flagged, and completes the plan, which deletes it and every attachment.

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Install](#install)
- [Connect an agent](#connect-an-agent): [Claude Code](#claude-code), [Codex](#codex), [VS Code](#vs-code-github-copilot), [Gemini CLI](#gemini-cli-google), [others](#other-clients)
- [Using it](#using-it)
- [Tools reference](#tools-reference)
- [Data and privacy](#data-and-privacy)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Development](#development)

## How it works

1. The app runs in the menu bar and serves MCP over Streamable HTTP at `http://127.0.0.1:47821/mcp` (port configurable).
2. An agent calls `create_test_plan` with cases and steps. A window titled with the plan opens, and you get a notification.
3. You work through the steps. Each gets a verdict, an optional note, and optional attachments.
4. The agent calls `wait_for_test_plan` to be woken as you go, reads failed and blocked steps with your notes, and calls `get_step_evidence` to see your screenshots and logs.
5. If a step comes back **Blocked** (you couldn't perform or verify it, usually because the agent's instructions didn't match the UI), the agent rewrites it with `revise_step` and you judge it again.
6. The agent calls `complete_test_plan`, gets a Markdown report, and the plan and its attachments are deleted from your disk.

Several plans can be active at once, from different agents, each with its own ID and window.

## Requirements

- macOS 26 or later
- Xcode 26 or later, to build it (there is no prebuilt binary)
- An MCP client that supports **Streamable HTTP** servers. Clients that can only launch local stdio servers can't connect.

## Install

```sh
git clone git@github.com:JoshuaSullivan/manual-test-plan-mcp.git
cd manual-test-plan-mcp
open ManualTestPlan/ManualTestPlan.xcodeproj
```

In Xcode, select the **ManualTestPlan** target, open *Signing & Capabilities*, choose your own team, then press **⌘R**. A checklist icon appears in the menu bar. The app has no Dock icon.

To keep it available permanently, either enable **Launch at login** in Settings, or archive the app (*Product › Archive › Distribute App › Copy App*) and move it to `/Applications`.

The menu bar popover shows the server status. It should read **Listening on port 47821**. If it shows an error, see [Troubleshooting](#troubleshooting).

## Connect an agent

The app must be running when the agent connects. Every client needs the same two facts:

| | |
|---|---|
| **URL** | `http://127.0.0.1:47821/mcp` |
| **Transport** | Streamable HTTP (`http`), no authentication |

If you change the port in Settings, substitute it everywhere below. The menu bar item **Copy MCP Setup Command** always copies the Claude Code command for the current port.

The clients below are configured as their documentation describes. I verified the server itself end to end with `Scripts/smoke-test.sh` (raw HTTP), not with each client, so if a client's flags have changed, the URL and transport above are the part to carry over.

### Claude Code

```sh
claude mcp add --transport http --scope user manualtestplan http://127.0.0.1:47821/mcp
```

`--scope user` makes it available in every project. Without it, Claude Code uses the *local* scope, which applies only to the project in the current directory. Use `--scope project` to write a `.mcp.json` you can commit for a team.

Equivalent `.mcp.json`:

```json
{
  "mcpServers": {
    "manualtestplan": {
      "type": "http",
      "url": "http://127.0.0.1:47821/mcp"
    }
  }
}
```

Verify with `claude mcp list`, or type `/mcp` inside a session.

### Codex

CLI, IDE extension, and desktop app all read the same config.

```sh
codex mcp add manualtestplan --url http://127.0.0.1:47821/mcp
```

Or edit `~/.codex/config.toml` (or `.codex/config.toml` in a trusted project):

```toml
[mcp_servers.manualtestplan]
url = "http://127.0.0.1:47821/mcp"
```

Leave out `bearer_token_env_var`, `http_headers`, and `auth`; the server needs none. Verify with `codex mcp list`, or type `/mcp` in the Codex TUI.

### VS Code (GitHub Copilot)

VS Code uses `servers` as the root key, not `mcpServers`. Copying a config from another client is the most common reason it doesn't appear.

Command line (writes to your user profile, so it works in every workspace):

```sh
code --add-mcp '{"name":"manualtestplan","type":"http","url":"http://127.0.0.1:47821/mcp"}'
```

Or per workspace, create `.vscode/mcp.json`:

```json
{
  "servers": {
    "manualtestplan": {
      "type": "http",
      "url": "http://127.0.0.1:47821/mcp"
    }
  }
}
```

Or use the Command Palette: **MCP: Add Server › HTTP**, then paste the URL.

Verify with **MCP: List Servers**. Then use Copilot Chat in **Agent** mode (tools are not available in Ask mode) and check that `manualtestplan` appears in the tools picker.

### Gemini CLI (Google)

Google's relevant product is [Gemini CLI](https://github.com/google-gemini/gemini-cli), which supports Streamable HTTP MCP servers.

```sh
gemini mcp add --transport http --scope user manualtestplan http://127.0.0.1:47821/mcp
```

`gemini mcp add` defaults to *project* scope, which writes `.gemini/settings.json` in the current directory. Pass `--scope user` unless you want that.

Or edit `~/.gemini/settings.json`. Note the key is `httpUrl`; a plain `url` key means the older SSE transport and will not work:

```json
{
  "mcpServers": {
    "manualtestplan": {
      "httpUrl": "http://127.0.0.1:47821/mcp"
    }
  }
}
```

Verify with `gemini mcp list`, or `/mcp` in a session.

### Other clients

Anything that speaks Streamable HTTP works with the URL above. Look for a setting named "HTTP", "Streamable HTTP", or "remote" server. Servers registered as "SSE" or stdio will fail: `GET /mcp` deliberately returns `405` because this server never streams.

Two things the server enforces that can trip up unusual clients:

- The `Host` header must be `127.0.0.1`, `localhost`, or `[::1]` with the configured port. A tunnel or reverse proxy that rewrites it is rejected.
- Any request carrying an `Origin` header is rejected with `403`. Browsers always send one; command-line and desktop agents don't.

## Using it

### Asking an agent to use it

Tell the agent what to test and that the check needs you. For example:

> I changed drag and drop on the kanban board. Make a ManualTestPlan test plan for the parts you can't verify, then wait for my results and fix anything that fails.

Agents learn the workflow from the server's built-in instructions and tool descriptions, so you shouldn't need to explain it.

### Finding the window

macOS doesn't let a background app take focus from the app you're working in, so a new plan's window may open **behind** your other windows. By default the app doesn't force it to the front, because a pinned window would cover the app you're testing. Instead:

- You get a notification when a plan is created (allow notifications when prompted).
- The agent is instructed to tell you in chat that the window is waiting.
- The menu bar icon changes and shows a count of plans that still need your attention. Click it and choose a plan to bring its window forward.

### Working through a plan

Each plan window shows the title, who created it, a progress bar with counts, and collapsible test cases containing steps. Each step has an instruction, an expected result, a verdict, a note, and attachments.

| Verdict | Use it when |
|---|---|
| **Passed** | You did the step and the result matched what was expected. |
| **Failed** | You did the step and the behavior was wrong. Say what you saw in the note. |
| **Blocked** | You couldn't do or verify the step. Typically the instruction doesn't match the real UI. Say what was different. The agent will rewrite the step. |

Choosing the same verdict again clears it. Choosing **Failed** or **Blocked** moves you into the note field. Choosing **Passed** jumps to the next unjudged step.

**Keyboard** (click a step first to focus it):

| Key | Action |
|---|---|
| `P` / `F` / `B` | Mark the focused step passed / failed / blocked |
| `↑` / `↓` | Move to the previous / next step |

Shortcuts are ignored while you're typing in a note.

**Attachments** can be any file up to 25 MB: screenshots, logs, crash reports, recordings, PDFs. Add them by:

- pasting (`⌘V`) with the step focused, which works for screenshots copied with `⌃⌘⇧4`,
- dragging files onto the step,
- clicking **Attach Files…**.

Images are normalized: PNG, JPEG, GIF, and WebP up to 3000 px are kept as-is, and anything larger or in another format becomes PNG, scaled down. Click an attachment for Open, Show in Finder, or Remove (Remove deletes the file immediately).

Once you scroll past the header, a floating bar keeps overall progress in view with **previous** and **next** buttons. They jump to the nearest step that has no verdict yet (opening its case if it was collapsed), wrapping around at the ends.

**Copy Report** in the plan window copies the current results as Markdown.

### What the agent sees

- **Notes** come back with the step in `get_test_plan`.
- **Images** come back as image content.
- **Text files** come back inline; very long ones keep their beginning and end (64 KB cap).
- **Other files** are described, and every attachment includes a `local_path` the agent can open directly.

### Settings

Open from the menu bar popover, or `⌘,`.

- **Port**: default 47821, allowed range 1024–65535. Change it, press **Apply and Restart Server**, and update your clients.
- **Keep plan windows on top**: plan windows float above other apps' windows, so they can't get lost behind the app you're testing. Off by default, because on a small screen a floating window can cover what you're testing. Takes effect immediately.
- **Launch at login**: starts the app at login. macOS may ask you to approve it in *System Settings › General › Login Items*.
- **Connect an Agent**: the Claude Code setup command, with a copy button.

### Completing a plan

An agent calls `complete_test_plan` when it's done. By default it is refused while any step is still pending, so an agent can't delete results you haven't finished; it can pass `force: true` to override. The report is always returned in the call before anything is deleted.

You can't complete a plan from the UI. Only the agent does, which is deliberate: it's the only party that knows it has finished reading your results. If an agent has gone away and left a plan behind, a later agent can find it with `list_test_plans` and complete it.

## Tools reference

| Tool | Purpose |
|---|---|
| `create_test_plan` | Create a plan of cases and steps and open its window. Returns the plan ID and the case and step IDs. |
| `get_test_plan` | Status and results. `detail: "summary"` (default) lists only failed and blocked steps with your notes; `"full"` lists every step. |
| `wait_for_test_plan` | Long-poll: returns when you record a verdict or attach a file after `since_revision`, or after `timeout_seconds` (default 30, max 60). Typing a note does not wake it. |
| `get_step_evidence` | Your note and attachments for one step. |
| `list_test_plans` | List active plans, optionally by keyword (matches IDs, titles, steps, and your notes). Recovers a plan ID after an agent loses its context. |
| `add_to_test_plan` | Append cases, or steps to an existing case, without disturbing your progress. |
| `revise_step` | Rewrite a step's instruction or expected result and reset it to pending. Your note and attachments are kept. |
| `complete_test_plan` | Return the final Markdown report, then permanently delete the plan and its attachments. |

If a client enforces a tool-call timeout shorter than 60 seconds, the agent can pass a smaller `timeout_seconds` to `wait_for_test_plan`.

## Data and privacy

Everything lives in the app's sandbox container, under `Application Support/ManualTestPlan/plans/<planID>/`:

```
plan.json
evidence/<id>.<ext>
```

- Plans survive quits and relaunches and can be recalled by ID or keyword.
- Completing a plan deletes its whole directory, including every attachment. If deletion fails, the call returns an error instead of claiming success.
- On launch, the app removes orphaned attachments that no plan references. It never deletes a plan file it can't read.
- Nothing is sent anywhere. The only network listener is the loopback MCP port.

To remove all data manually, quit the app and delete `~/Library/Containers/com.joshuasullivan.ManualTestPlan/Data/Library/Application Support/ManualTestPlan`.

## Security

The server binds to `127.0.0.1` only, so other machines can't reach it. It rejects requests with a browser `Origin` header or an unexpected `Host`, which blocks web pages and DNS-rebinding attacks. It limits headers to 16 KB and bodies to 4 MB.

There is **no authentication**. Any process running as you can create, read, and complete plans. That matches the trust level of the agents you're running, but it means you shouldn't run untrusted local software next to it, and you shouldn't expose the port with a tunnel.

`local_path` values returned to agents point only at attachment files inside the app's own storage.

## Troubleshooting

**The agent can't connect.** Confirm the app is running and the popover says *Listening on port…*. Then check the server directly:

```sh
curl -s -X POST http://127.0.0.1:47821/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'
```

An `{"jsonrpc":"2.0","id":1,"result":{}}` reply means the server is fine and the client config is wrong.

**The server status shows an error or "port in use".** Another process owns the port. Pick a different one in Settings and update your clients. Check what's using it with `lsof -nP -iTCP:47821 -sTCP:LISTEN`.

**The client connected but shows no tools.** VS Code: make sure you're in Agent mode and used `servers`, not `mcpServers`. Gemini CLI: use `httpUrl`, not `url`. Most clients cache the tool list, so restart the session after adding a server.

**403 errors.** The request has an `Origin` header, or a `Host` that isn't loopback plus the configured port. See [Other clients](#other-clients).

**I can't find the plan window.** Click the checklist icon in the menu bar and choose the plan. See [Finding the window](#finding-the-window).

**No notifications.** Allow them in *System Settings › Notifications › ManualTestPlan*.

**A plan was left behind.** Ask any agent to `list_test_plans` and `complete_test_plan` with `force: true`.

## Development

Open `ManualTestPlan/ManualTestPlan.xcodeproj` (Xcode 26+, macOS 26+). The app is Swift 6 with strict concurrency, SwiftUI, `@Observable`, and no third-party dependencies. MCP and HTTP are implemented directly on Network.framework.

```
ManualTestPlan/ManualTestPlan/
  Models/        plan, case, step, status, and Markdown report types
  Persistence/   actor that reads and writes plans and attachments
  Store/         PlanStore, the single source of truth for the UI and the tools
  MCP/           JSON-RPC router, tool definitions, HTTP parsing and server
  Attachments/   paste, drop, and file-picker handling
  App/           app model, notifications, launch at login
  Views/         menu bar, plan window, settings
```

Run the unit tests with **⌘U** in Xcode. They cover the models, persistence, store, MCP router, tools, and HTTP parser. The test host is sandboxed without outbound network access, so wire-level behavior is covered by a script that talks to the running app:

```sh
Scripts/smoke-test.sh          # app must be running
Scripts/smoke-test.sh 50123    # or pass the port
```

The script creates a plan, exercises every tool, and completes it, so it leaves nothing behind.
