# AGENTS.md

## Project Overview

Cylinder Reborn is a jailbreak tweak that animates Home Screen icons as you swipe between pages. It is a
modernized continuation of the classic tweaks Cylinder and Barrel.

- More than 60 page-transition effects, such as cube folds, shrinking, and spinning.
- Effects are Lua scripts installed to `/Library/Cylinder`, so users can write or modify their own.
  `scripts/EXAMPLE.lua` documents the API scripts can use.
- Supports iOS 11 and later: rootless packages for iOS 15+, rootful packages (`ROOTFUL=1`) for iOS 11-14.
- Cylinder Remade (`../Cylinder-Remade`) is the Swift port for iOS 14+, with the effects compiled in.

## Branches

- `master` (`../Cylinder-Reborn`) holds only the tweak.
- `testing` (this worktree, `../Cylinder-Reborn-testing`) is one commit on top of `master` that adds the
  simulator tooling: `tweak/CylinderSimHarness.m`, every `CYLINDER_SIMJECT` block, `scripts/run-simject.sh`,
  `make simject`, and this file.
- Commit tweak changes on `master`, then run `git rebase master` here. Never commit harness hooks,
  `CYLINDER_SIMJECT` code, or simulator notes to `master`.

## Build & Development Commands

```
make package              # rootless package, iOS 15+
make package ROOTFUL=1    # rootful package, iOS 11-14 (needs Xcode 11's toolchain, see Makefile)
```

| Path | Purpose |
|------|---------|
| `packages/` | Build output (.deb files) |
| `control` | Debian package metadata (name, version, depends) |
| `Makefile` | Theos build config |
| `lua/` | Lua 5.5 submodule, built as one file from `lua/onelua.c` |
| `scripts/` | The effect scripts the package installs |

## Theos & Logos Conventions

- Use Logos directives (`%hook`, `%orig`, `%group`, `%ctor`) for runtime patches
- Keep related hooks grouped together
- **`%orig` passes original arguments**: `%orig;` always calls the original method with the original captured arguments, even if you've reassigned the local parameter variables. To pass modified values, use explicit arguments: `%orig(arg1, modifiedArg2, arg3)`.
- **`MSHookIvar` only works inside `%hook` blocks**: It's a Logos macro. In static helper functions, use `class_getInstanceVariable` + `object_getIvar` from the ObjC runtime instead.
- **Avoid layout-driving writes inside `layoutSubviews` hooks**: Writing `frame`, `bounds`, `layoutMargins`, or other Auto Layout inputs from `layoutSubviews` can loop during rotation. Do one-shot preparation from non-layout entry points.

No automated test suite, must be validated manually.

## RE Notes

### Handy Hopper MCP Tools

- `Hopper/list_documents`, `Hopper/set_current_document`: select the document for the binary you need, such as SpringBoardHome
- `Hopper/goto_address`: jump to an address (static address Hopper uses)
- `Hopper/current_procedure`: find which function the current address is in
- `Hopper/procedure_pseudo_code`, `Hopper/procedure_assembly`: decompile/disassemble the function
- `Hopper/search_procedures`: find functions by name/regex (works well for ObjC methods)
- `Hopper/search_strings`: search embedded strings (bundle IDs, selectors, product identifiers, URLs)
- `Hopper/xrefs`: find references to a string or address
- `Hopper/list_segments`, `Hopper/list_names`: quick orientation for the binary layout
- `Hopper/procedure_callers`, `Hopper/procedure_callees`: trace call graphs (who calls this? what does this call?)

### Effective Hopper Investigation Patterns

**Discovering class layout via `.cxx_destruct`**: Search for `-[ClassName .cxx_destruct]` and decompile it. This reveals every ivar in the class, their types (ObjC objects use `objc_release`, Swift structs use type metadata accessors, bridged objects use `swift_bridgeObjectRelease`), and their ivar offset symbols. This is the fastest way to understand a class's storage layout.

**Tracing from a known entry point**: When you know the ObjC method, decompile it to find the `sub_XXXX` helper it delegates to. Then decompile that helper. This "peel the onion" approach finds the actual logic buried under thunks and wrappers.

**Fix transition bugs at the source**: For Home Screen scroll and app-launch/close transition bugs, start from the SpringBoard method that initiates the behavior (the scroll delegate, the icon zoom or crossfade setup, the completion block that cleans it up) and trace forward in Hopper before adding new hooks. Durable fixes come from understanding the native transition or its async completion first, not from stacking more downstream hooks.

**Pseudocode constant folding of base registers**: Hopper's decompiler sometimes loses track of a base register and folds it into offset constants, producing misleading absolute-looking addresses. For example, if the assembly is `madd x8, x21, x8, x22` then `str w0, [x8, #0x20]` (meaning `buffer + index*stride + 0x20`), the pseudocode may render this as `*(stride * index + 0x50)` — collapsing `buffer + 0x20` into a single constant `0x50`. This is a critical trap: the pseudocode appears to say elements start at offset 0x50, when they actually start at buffer+0x20. **Always verify struct/array element offsets from the raw assembly** (look for `madd`/`add` base register calculations and `ldr`/`str` displacement operands) rather than trusting the pseudocode constants.

### Mapping Runtime PCs To Hopper Addresses

Crash logs typically show:

- A loaded image base, e.g. `SpringBoardHome 0x1a2b3c000 + 7746680`
- A program counter (PC), e.g. `0x1a32a5478`

The offset is `PC - imageBase`. Hopper usually uses a Mach-O "file base" of `0x100000000`, so:

- `hopperAddr = 0x100000000 + (PC - imageBase)`

Once you have `hopperAddr`:

- `Hopper/goto_address` -> `Hopper/current_procedure` -> decompile around the trap/crash site.

## Headers And Runtime Introspection Tips

- For methods you only need to call defensively, prefer `objc_getClass` + `NSSelectorFromString` + `objc_msgSend` over adding brittle headers.
- If a class is only forward-declared, cast the object to its nearest public superclass (or `id`) before sending UIKit messages to keep clang happy.

## iOS tweak simulator workflow

- This repository is a Theos/Logos jailbreak-tweak project.
- Preserve physical-device builds.
- Simulator testing uses simject in `/opt/simject`.
- Apple Silicon simulator builds use:
  `TARGET=simulator:clang::12.0 ARCHS=arm64`
  Cylinder Remade's Swift code needs iOS 14, so build it with `TARGET=simulator:clang::14.0`.
- Intel simulator builds use:
  `TARGET=simulator:clang::7.0 ARCHS=x86_64`
- `make simject` (`scripts/run-simject.sh`) builds and installs everything; set `SIMULATOR_UDID` to pick a device.
- Install both the simulator dylib and its matching filter plist.
- Ad-hoc sign the copied dylib.
- Run `resim -i <simulator-UDID>` after every installation.
- For app-targeted tweaks, terminate and relaunch the filtered bundle after
  running resim.
- For SpringBoard tweaks, resim performs the necessary process restart.
- Verify injection through the unique `[CylinderSimject]` log prefix.
- Never remove `/opt/simject/simject.dylib` or
  `/opt/simject/simject.plist`.
- Do not run first-time Simject installation scripts, modify Xcode runtimes,
  use sudo, or modify Theos vendor files without explicit approval.

## Simulator harness (simject builds only)

`tweak/CylinderSimHarness.m` (also in Cylinder Remade) compiles only with `CYLINDER_SIMJECT=1`. Write
`~/Library/Cylinder/.harness.plist` inside the simulator's data directory, then run
`xcrun simctl spawn <udid> notifyutil -p com.ryannair05.cylinder.harness`.

- `command` = `launch` (`page`, `index`): taps an icon to open its app.
- `homeScroll` (`delayMs`, `fraction`, `durationMs`, `holdMs`): presses Home, then drags the Home Screen while
  the app zooms back into its icon. This reproduces the crossfade handoff bug. `noHandoff = 1` disables the fix.
- `flyInScroll` (`lockMs`, `delayMs`, `modelMs`, plus `scroll`'s keys): shows the Lock Screen, dismisses it after
  `lockMs` so the icons fly in, and drags the Home Screen `delayMs` into the fly-in. During the fly-in SpringBoard
  moves the page's icon views into a zoom container on the page, so Reborn's page context sees none of them.
  `modelMs` (comma-separated) logs each icon's superview, frame, model and presentation `zPosition`, sublayer index
  and transform at those times. SpringBoard springs each icon's presentation `zPosition` with staggered timing.
- `folderClose` (`page`, `index`, `openMs`, `delayMs`, `folderTraceMs`, plus `scroll`'s keys): opens the folder at
  `index` (the first folder icon when absent), presses Home after `openMs` and drags the Home Screen `delayMs` into
  the close. Each frame it logs the folder icon's on-screen corners next to the `SBFolderContainerView` that
  SpringBoard's `SBFolderSourceViewTrackingMatchMoveAnimation` keeps on the icon's page, and whether Cylinder steers it.
- `pose` (`page`, `fraction`, `name`): holds one scroll position, writes a screenshot and a JSON dump of every
  page and icon layer to `~/Library/Cylinder/shots`. Compare Reborn and Remade dumps for effect parity. It also logs
  each visible page, custom pages such as the Today view (`page` = -1) included, with its transform and how many
  icon layers draw antialiased edges.
- `traceMs` (any command): logs the presentation-space rects of the launched icon and of the flight each frame, plus
  whether SpringBoard's `MatchMoveToIconViewAnimation` is attached and Cylinder's steering on it.
- `coords` (`page`): logs every icon's raw `SBIconCoordinate` and frame, and the origin probes.
- `bench` (`frames`, `flush`): runs synchronous scroll frames through SpringBoard and logs the mean cost.
- `page`: SpringBoard's own animated page change. `state`, `order`, `geom` log layout details.

Device builds (`make package CYLINDER_SIMJECT=1`) include the harness too; with no log reader on rootless
jailbreaks it appends to `/var/mobile/Library/Cylinder/harness.log` instead of NSLog.

Programmatic `setContentOffset:` is reset by SpringBoard unless BaseBoard believes a drag is in progress, so the
harness reports `isDragging`/`isTracking` for the root icon scroll view while it drives it.
Benchmark with `FINALPACKAGE=0 DEBUG=0` to keep Theos's debug flags out of the tweak. The Lua VM always builds at
`-O2`, because its per-file flags in the Makefile come after Theos's optimization level.
