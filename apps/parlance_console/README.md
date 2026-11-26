# Parlance Console

Open **Parlance Console.command** on macOS or run it from this directory:

```sh
"./Parlance Console.command"
```

The launcher uses the workspace Flutter SDK through FVM to build the native window. It connects to the collector at `~/.parlance/mcp.sock`. When there is no collector it starts the one in `parlance_mcp` on `ws://127.0.0.1:9500`. Other local agents can connect using `nc -U "$HOME/.parlance/mcp.sock"`. Closing the launcher’s window stops its own collector. A collector already running (for example through Rhyolite’s LAN proxy) keeps serving its other clients.

Open **Wi-Fi**, enable **Accept devices over Wi-Fi**, then copy the address for your phone into its collector settings. Use the same local network as the Mac. The launcher saves the setting and starts the listeners again next time. Switching it off or closing the launcher disconnects Wi-Fi clients. Android uses WebSocket on port 9444. For iPhone, install `mkcert` on the Mac, install `rootCA.pem` from `mkcert -CAROOT` on the phone and enable full trust in Certificate Trust Settings. The launcher creates the TLS certificate for the current LAN address and serves WSS on port 9443. The local MCP socket stays private.

Select a device under **Logs** to follow its latest 200 records, pause updates or filter by minimum level and trace ID. **Inspector** shows the selected host’s states, facts and commands. Select a word to read it, explain a change, inspect its recent facts or invoke a command when the host permits it. **Journal** opens recorded files. Opening the macOS app directly or running the web build opens the offline journal viewer.

**Journal → Live** follows the selected host about once per second. Pause the
feed to inspect a conversation, then resume from the same cursor. The console
reports gaps when the host has evicted entries. Hosts opt in with
`CollectorHost(shareJournal: true, …)`. For older hosts or collectors the
Live tab can follow the latest facts of a selected word. **Journal → Files**
opens saved recordings independently.

## Journal playback

Conversations of a parlance journal (`parlance_journal`'s JSON lines),
loaded, drawn and played back. Runs in a browser and on macOS.

- **Open or drop** journal files (`journal-2026-10-28.jsonl`; several days at
  once go in the order of their days). In a browser, `?journal=<url>` opens
  the journal at that address, relative to the viewer's: a link to a journal
  opens it.
- **Conversations**: when each started, the word it started with and who
  (its origin), how long it went on, how many entries, and its calls
  refused, failed or timed out. Search by any recorded word, state key, who or id; *Problems* keeps
  those with a refusal, a failure, a timeout, cancellation or a lost reply.
- **A conversation** as a tree on its time: each message under the one it
  followed from, a call as a bar from its start to its end, a fact and a
  write as a mark; colours tell how a call ended.
- **A message**: who, when, what it follows from, its conversation and
  origin, its trace, how a call ended and why, its values, how it came about
  (the path from the first message), and the entry as written.
- **Evidence**: incomplete parents, ambiguous identities, omitted values and
  unreadable fragments are explicit. Admission and retry decisions expand under
  the operation. A state change opens its history across conversations; a history
  item opens the conversation which caused it. Stream lifecycle is recorded
  without retaining its elements.
- **Playback**: the playhead goes over what was loaded at 1×, 10×, 60× or
  600×, jumping quiet stretches; the list and the tree show only what had
  happened by then. Stop shows everything again.

```sh
fvm flutter run -d chrome            # or -d macos
fvm flutter build web --no-web-resources-cdn   # self-contained, to serve anywhere
fvm dart run tool/sample_journal.dart          # a sample journal to look at
```
