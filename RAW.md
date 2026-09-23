# Visual Workplace — portable raw build (ColorForth + Dylan + Evoke BEAM)

This package is **offline**. It does **not** depend on a preview hosted on
someone’s box, `python -m http.server`, localhost, or any network service.
The product is **raw code**: ColorForth `.cf` vocabulary + an Open Dylan–style
library + the Evoke BEAM (Elixir/OTP) agent mesh you can point real toolchains at.

Optional HTML (if present under `build/out/workplace-standalone.html`) is a
**convenience** `file://` viewer with everything inlined. It is **not required**
to have or use the ColorForth / Dylan sources.

## Quick start

```bash
unzip evoke-visual-workplace-raw.zip
cd evoke-visual-workplace
./evoke
```

`./evoke` copies/assembles sources into `build/out/`, writes `MANIFEST.txt`,
emits `build/out/colorforth/WORKPLACE.CF`, copies the Dylan library and
`raw/beam/` → `build/out/beam/`, writes `bridge-map.json` (CF ↔ Dylan ↔ BEAM),
and optionally emits the standalone HTML. Exit 0 on success.
**Zero network.**

## Layout

```
evoke-visual-workplace/
├── RAW.md                 ← this file
├── evoke                  ← build evocator (shell)
├── raw/
│   ├── colorforth/        ← pure .cf only
│   │   ├── 00-boot.cf … 05-screen-termux-agent.cf
│   │   ├── blocks.cf      ← full concatenated vocabulary
│   │   ├── desktop.cf, workbench.cf, termux.cf, agent.cf, …
│   │   └── workplace.cf
│   ├── dylan/             ← Open Dylan–style library
│   │   ├── visual-workplace.lid
│   │   ├── library.dylan, module.dylan
│   │   ├── events.dylan, ui.dylan, app.dylan
│   │   ├── evoke-build.dylan   ← start-visual-workplace / evoke-visual-workplace
│   │   └── evoke-bridge.dylan  ← DYLN mesh notes → on-dylan-event
│   └── beam/              ← Evoke BEAM mesh (Elixir / OTP, from Apple Swarm)
│       ├── mix.exs
│       ├── lib/evoke/{application,agent_node,agent_supervisor,
│       │              backpressure,dylan_protocol,workplace_bridge,
│       │              telemetry,transport/websocket}.ex
│       └── test/evoke/*_test.exs
├── scripts/
│   ├── frame_smoke.py     ← pure-Python DYLN encode/decode smoke
│   └── embed_standalone.py
├── optional/preview/      ← used only by evoke to inline standalone HTML
└── build/out/             ← filled by ./evoke (do not hand-edit; re-run evoke)
```

## ColorForth color annotations

Plain text cannot carry Chuck Moore’s display colors. In these sources, color
is carried as **educational prefix words** (or classic CF color tags):

| Prefix / tag | Color   | Meaning |
|--------------|---------|---------|
| `red`        | #ff3030 | **Define** a word |
| `green`      | #30ff30 | **Compile** into definition |
| `yellow`     | #ffff30 | **Execute** immediately |
| `cyan`       | #30ffff | **Comment** |
| `white`      | #f0f0f0 | **Literal** / number |
| `magenta`    | #ff40ff | **Macro** / immediate |

Example:

```
cyan desktop shell
red shell
  green wallpaper
  green menubar
  ;
yellow shell
```

A ColorForth machine would assign colors from boot blocks; here the prefixes
document intent so the vocabulary stays readable without an HTML viewer.

### What a ColorForth machine would consume

- **Preferred:** `build/out/colorforth/WORKPLACE.CF` (or `raw/colorforth/blocks.cf`)
  — single stream: desktop, workbench, termux (incl. `c-live`), agent, demo screen, boot.
- **Or:** numbered blocks `00-boot.cf` … `05-screen-termux-agent.cf` in load order
  `01→02→03→04→05` then execute `00-boot` / `workplace`.

This is educational CF-style vocabulary, not a claim of a full Chuck Moore
CPU image. Simulation notes: syscall / gcc / Termux traces are didactic.

## Dylan — what Open Dylan would consume

```bash
cd build/out/dylan   # or raw/dylan
dylan-compiler -build visual-workplace.lid
# then run the produced binary, which calls main → boot-workplace
```

App entry points:

| Function | Role |
|----------|------|
| `main` | CLI entry (prints stub status) |
| `boot-workplace` | Builds `<visual-workplace>`, mounts Termux\|Agent |
| `start-visual-workplace` | Alias of `boot-workplace` (`evoke-build.dylan`) |
| `evoke-visual-workplace` | Prints evoke confirmation |

Library modules: `visual-workplace-events`, `visual-workplace-ui`, `visual-workplace`.

This box may not ship `dylan-compiler`; the `.dylan` / `.lid` files are the
portable artifact.

## Bridge map

`build/out/bridge-map.json` maps ColorForth words to Dylan methods/classes
and Evoke BEAM modules (e.g. `do-gcc` ↔ `compile-c!` ↔
`Evoke.WorkplaceBridge.fan_event(:compile_c)`). Raw JSON data only —
not a running bridge server.

## Optional standalone HTML

If `./evoke` finds `optional/preview/`, it writes
`build/out/workplace-standalone.html` with `bridge.js` **inlined** and raw
CF/Dylan embedded as JSON. Open via `file://` — **no fetch**, no localhost.

Preview HTML is optional educational chrome. **Raw `.cf` + `.dylan` are the
product.**


## Evoke BEAM mesh (Elixir / OTP)

Sources live in `raw/beam/` (extracted from Apple Swarm) and are copied to
`build/out/beam/` by `./evoke`.

```bash
cd build/out/beam   # or raw/beam
mix test            # requires Elixir ~> 1.16 + OTP; offline, zero Hex deps
```

If Elixir is not installed on this machine, run the pure-Python smoke instead:

```bash
python3 scripts/frame_smoke.py
```

### How Dylan frames ride the mesh

UI events become DYLN frames (`magic "DYLN"`, opcode `0x01`–`0x07`, body,
CRC32-IEEE over the body) via `Evoke.DylanProtocol` / `Evoke.WorkplaceBridge`.
`WorkplaceBridge.fan_event/3` asks an `AgentNode` to encode the frame and
`Registry.dispatch` it on the `"dylan_transport"` topic so every transport
(WebSocket, collectors, tests) receives `{:dylan_frame, packet}`. Inbound
packets decode back to event kinds (`:open_file`, …) which map 1:1 to Dylan
`on-dylan-event` symbols (`#"open-file"`, …) documented in
`raw/dylan/evoke-bridge.dylan`.

`bridge-map.json` triples ColorForth words ↔ Dylan methods ↔ BEAM modules.

## Constraints / non-goals

- Does not delete or replace `/workspace/visual-workplace-colorforth-dylan/`
  or `/workspace/visual-workplace/` (those remain the upstream sources).
- No dependency on the author’s machine after you download the zip.
- Real Termux / gcc / kernel are **not** included — command traces are simulated
  in the preview / Dylan stubs.
