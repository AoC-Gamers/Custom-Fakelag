# Windows SRCDS shutdown investigation

The current failure has a reproducible configuration/lifetime mechanism: with `sv_lan 1`, a map transition invalidates Steam interface objects still cached by `server.dll`; subsequent use can fault before any `quit` command. Vanilla reproduces it without any plugin. Changing only the private configuration to `sv_lan 0` preserves the sampled interfaces and permits clean disconnect/quit; restoring `sv_lan 1` reproduces `0xc0000005`. This establishes the current configuration-dependent reproduction, not a universal explanation for every historical exit code. No production fix is included. The functional acceptance from the previous load-order investigation remains separate.

## Scope and fixed inputs

Production base: `65031fb83da9b1ce9487237c3a19e83735c02686`; production DLL source: `9c7debcf334ef534d715449b828e0c6d5fa67853`. Only investigative tools and documentation change on `codex/windows-shutdown-investigation`. There is no product fix, deployment, push or PR.

The normal PE32 DLL SHA-256 is `3e062b7047baad8551c5bd384fa18f9727735418ad917f60a04d155589165a73`; engine SHA-256 is `8a6d468059394bf4cfce32f11dcba12ef45de88da1373084d5a2916d0bf7ba86`. SourceMod/DHooks 1.12.0.7260, Metamod 1.12.0-dev+1229, Left4DHooks 1.175 from `7672bdefc4e03a693ae7fdc06e470df41b4cc069`.

The private server uses copied core executables and writable game/configuration directories. Absolute SearchPaths reuse the official dedicated installation's game assets. Neither a complete duplicate game nor writable hardlinks are used. The desktop Steam client and both installed games are preserved. SteamAppId is 550; SteamGameId/overlay metadata is 222860. The official dedicated `bin/steamclient.dll` is selected briefly through HKCU, verified in the server's actual modules and restored in `finally` before client connection. No Steam restart occurs in this window.

## Protocol and tools

Each row is a fresh owned process on `c1m1_hotel`, with the same authenticated real Steam client. After observing the playable map and issuing one jump input, the controller checks one human, resolved Steam identity and the server's authentication event. It then records 15 seconds with the human remaining connected and sends `quit` from the private console. This is a short playable network session, not an extended campaign stress test. Loading and authentication time precede the defined interval and vary between trials.

`scripts/start-windows-shutdown-trial.ps1` starts one row; `tests/windows_shutdown_trial.py` validates loaded components and detour bytes before accepting it. Append `@run` to the trial's initially empty command file only after the real client reaches gameplay. The `connected`, `detached` and `idle` scenarios are distinct. Detached uses the authenticated human's `kickid`, verifies zero humans, then quits. Idle requires zero humans throughout.

The controller holds the actual child process handle through shutdown, waits up to 90 seconds and cross-checks Python's exit code with Win32 GetExitCodeProcess and a signaled process handle. A timeout or collector error leaves the process explicitly alive, never labelled a clean shutdown. No forced termination is used to manufacture success. Six collection regressions passed: real fixture exits 0, 23, `0xc0000005`, `0xc0000409`, an unsignaled timeout, and a native PE32 DLL-detach window where exit status 23 is already available while the process is still unsignaled. The last fixture exposed why the adopted-process helper must check the handle before trusting a status. The helper is corrected; this observation alone does not invalidate an old trial with independently signaled completion.

Raw consoles stay private. `tests/export_windows_shutdown.py` exports selected fields without console contents, registry values, SteamIDs, player names or addresses. Snapshot module hashes are labelled as measured during the trial or at export. An exit code alone is never exported as a captured exception record.

## Effective configurations

| Row | Components |
|---|---|
| A | Vanilla, no Metamod/SourceMod/DHooks/Custom-Fakelag |
| B | Metamod + minimal SourceMod |
| C | B + DHooks |
| D | C + Left4DHooks + minimal forward consumer |
| E | C + normal Custom-Fakelag |
| F | D, then Custom-Fakelag after FillServerInfo E9 becomes active |
| G | E, then the same consumer and Left4DHooks |

All stock and optional plugins are disabled, including player_fakelag and BuiltinVotes. Left4DHooks additionally requires BinTools, SDKTools and SDKHooks; their actual loaded modules/extensions are part of the observation. These dependencies are a difference between C and D, not an implicit proof that Left4DHooks alone caused any later difference.

The minimal `tests/windows_shutdown_fill_consumer.sp` implements only `L4D2_OnClientDisableAddons`, returning `Plugin_Continue`; it neither changes addon policy nor calls Custom-Fakelag. It is identical in D/F/G. In Left4DHooks' `CheckRequiredDetours`, the forced-detour check is inside iteration over plugins excluding itself. With no other plugin the library can be running while FillServerInfo remains original. This was observed in excluded pilots. Adding the consumer activated the expected E9; the controller verifies the actual bytes and executable target region. No manual engine-byte restoration or validator changes are made.

Excluded pilots are kept privately: an initial B with missing SourceMod VDF (Metamod only), and two D setups with a registered library but inactive FillServerInfo. They do not count toward the matrix.

## Historical evidence and limitations

### New baseline matrix

All 35 baseline trials exited 0 with matching Python/Win32 codes and signaled process handles. These all use `sv_lan 1` and **no map change**:

| Row | Quit with human connected | Disconnect, verify zero humans, quit | No client, quit |
|---|---:|---:|---:|
| A | 3/3 | 1/1 | 1/1 |
| B | 3/3 | 1/1 | 1/1 |
| C | 3/3 | 1/1 | 1/1 |
| D | 3/3 | 1/1 | 1/1 |
| E | 3/3 | 1/1 | 1/1 |
| F | 3/3 | 1/1 | 1/1 |
| G | 3/3 | 1/1 | 1/1 |

The connected orders were A,B,C,D,E,F,G; G,F,E,D,C,B,A; D,A,F,C,G,B,E. Authentication was verified for every connected and disconnected baseline. The defined activity is 15 seconds; loading, inspection and attachment time vary and are separately timestamped. This is evidence for these short sessions, not proof that arbitrary longer sequences cannot fail.

### Extended controls and intervention

| Trial | Difference from baseline | Actual result |
|---|---|---|
| F_connected_10 | Zero-profile public API sequence, reset, 3 CF unload/reloads, map change, real-client kick; LAN 1; no debugger | `0xc0000005`, signaled, before quit; no dump |
| F_connected_11 | Instrumented repeat; LAN 1 | Final SM read AV `+0x13b63`; interruption makes its exact initiating trigger uncertain |
| A_detached_10 | Vanilla, map change then kick; LAN 1; no debugger | Collector error; later process disappeared; exit code unknown |
| A_detached_11 | Vanilla, late CDB after map; LAN 1 | Initial invalid execute target from server `+0x1e1226`; final engine read AV `+0x161316`; supplemental signaled exit `0xc0000005` |
| A_detached_12 | Vanilla, hardware writes watched before map; LAN 1 | Same call site, execute address zero; final engine `+0x161316`, actual `0xc0000005` |
| A_detached_13 | Vanilla, desktop steamclient instead of dedicated runtime; LAN 1; no debugger | Authenticated, cached vtable invalid after map, actual `0xc0000005` on kick |
| A_detached_14 | Vanilla, only server.cfg LAN setting changed to 0; official runtime; no debugger | Interfaces remain valid; zero humans verified after kick; quit actual 0 |
| A_detached_15 | Exact original server.cfg restored: LAN 1; official runtime; no debugger | Fault reintroduced: actual `0xc0000005` on kick, before quit |
| F_connected_12 | Same extended zero-profile sequence as F10, with LAN 0; includes successful reconnect | All 3 unloads verified; zero profiles after disconnect; authenticated new session; quit with human still connected: actual 0 |
| F_connected_13 | Matched LAN-0 staged sequence with active public-API profiles | Latency/Bernoulli/GE/reset, 3 verified unload/reloads, map, kick, reconnect; quit with human and 120ms profile active: actual 0 |

BuiltinVotes and player_fakelag were never loaded in these trials. Their optional dependency was recovered privately for possible historical reproduction, but the minimum already reproduces in vanilla. Their presence as disabled files is not a loaded module. SourceMod, DHooks, Left4DHooks and Custom-Fakelag are absent from the actual A module inventory.

The F10/F11 exploratory long sequence changed several operations and cannot isolate an individual operation by itself. The subsequent vanilla controls remove all plugin operations and narrow the current reproduction to map/Steam lifecycle plus a real-client disconnect. F12 repeats the long no-profile control under the single LAN intervention. The active-profile comparison is reported separately below; operations are added in stages with equivalent zero-profile controls, not presented as independent randomized stress trials.

Previously reported real-client exits were `0xc0000409` (Left4DHooks first, PID 10216) and `0xc0000005` (reverse order, PID 21292); earlier vanilla also had `0xc0000409`. New idle references from the prior task exited 0. The old process dumps were removed during the user's explicitly authorized cleanup before this assignment; retained textual traces cannot recover their missing object memory or fast-fail parameters.

An older textual live-debug trace reports a first-chance read AV at `server.dll+0x1e121d`, address `0x28`. The debugger was subsequently quit, so this is not by itself proof of the final unhandled exception. Another retained shutdown minidump analysis reports `sourcemod.2.l4d2.dll+0x13b63`, reading `[ecx+4]` with ECX zero during loader shutdown. Detection in that destructor does not identify the writer or original invalidation. Neither trace establishes Custom-Fakelag as the cause.

The new private instance was reconstructed after cleanup. Its minimal component set, fresh process sequence and copied writable layout differ from the former long API/reload/map-change sessions. Absence of failure in the short baseline cannot rule out those sequences or runtime lifecycle effects.

### Candidate object behind the historical server AV

Offline disassembly of the currently installed `server.dll` (SHA-256 `a93ec916a8f26fbea85688c321d2ba8dd346d435fab09a0b926dd950c2e1ea12`) gives the following data flow:

```text
server+0x1e1213 call server+0xed4a0     ; returns server+0x7f77dc
server+0x1e1218 mov ecx,[eax+4]        ; cached interface pointer
server+0x1e121b mov eax,[ecx]          ; interface vtable
server+0x1e121d mov eax,[eax+0x28]     ; historical read AV: EAX=0, address 0x28
server+0x1e1224 call eax
```

The function first checks the cached pointers at context offsets +4 and +8 for zero; that does not validate the first word of either pointed-to object. The retained old registers have nonzero ECX but zero EAX, consistent with an invalid or cleared vtable. The original server binary hash and object memory were not retained with that text trace, so matching the present instructions is not proof of an identical historical binary or allocation lifetime.

`tests/windows_shutdown_context.py` reads this context only after checking the owned launch receipt and exact current server hash. In fresh vanilla PID 3980, its +4 object had a nonzero vtable in `steamclient.dll+0xebb930`; slot +0x28 pointed to `steamclient.dll+0x535b20`. The +8 object was also valid at the sampled instant. This narrows the candidate object to a Steam runtime interface, without proving the historical invalidator. A first tooling pilot lacked VM_READ access and returned unreadable fields; it is excluded, retained privately, and the corrected snapshot records read errors explicitly.

The method-slot pattern is consistent with a cached Steam game-server API context and a GetSteamID call, but the exact interface name remains an inference. The [Valve SDK interface declaration](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/steam/isteamgameserver.h) places GetSteamID at slot 10; the current SDK is not established as the exact L4D2 SDK. Valve's [game-server API header](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/steam/steam_gameserver.h) describes shutdown freeing interface/resources. Those headers provide context; the following new observations provide the process-specific evidence.

### Observed invalidation and later use

A12 attached before map change with live +4 and +8 objects. Hardware write watches covered each object's first word and the cached +4 pointer. On map change, writes to both first words stopped in `tier0_s!TSListBase_Push+0x30`, in a chain through Steam's allocator/runtime and `steam_api!SteamGameServer_Shutdown`, called by `engine+0x121a39`. The +4 object address remains the same one later in ECX at the failing indirect call. Its first word was subsequently overwritten/reused; there was no watched replacement of the cached +4 pointer before use. Representative sanitized chain:

```text
tier0_s!TSListBase_Push+0x30
tier0_s + allocator frames (export-relative names are approximate)
steamclient + runtime frames
steam_api!SteamGameServer_Shutdown+0x4d       ; object +4 write
engine+0x121a39
engine+0x123b0a
engine+0x18d30a
```

The +8 write has the same engine chain with `SteamGameServer_Shutdown+0x6d`. These are CPU hardware observation breakpoints, not patched engine bytes or manual cache repair. Hardware stops affect timing; the uninstrumented A13/A15 and F10 independently prove the failure is not exclusive to a debugger.

Later A12 tries to execute zero, with caller return address `server+0x1e1226`, immediately after `call eax` in the data flow above. A11 reaches the same call site with an invalid nonzero execute target. This explains why related stale-object states can produce different addresses/operations; matching exit codes alone would not demonstrate it. The first AV is passed to the application's handlers with `gn`, not marked handled to manufacture a clean result.

Both vanilla captures then enter `ExitProcess(-1)` and loader teardown, and end in a second-chance read AV at `engine+0x161316`, instruction `mov eax,[ecx+0xd0]`, with invalid memory. That final engine detection is later than the cached-interface failure. F11 instead ends at SourceMod `ConCommandCleaner::UnlinkConCommandBase+0x13`, reading address 4 during the same kind of loader teardown. Matching SourceMod symbols identify that function, but F11's interrupted trigger prevents a claim that it has exactly A12's initiating sequence.

Under `sv_lan 0`, A14 snapshots retain the same valid Steam vtables (`+0xebb930`, `+0xec1380`) across map change and the actual process exits 0 after verified disconnect/quit. A15 restores the exact LAN-1 config bytes and fails again, without debugger. The controlled configuration intervention eliminates the observed invalid-object state and failure in its tested scope. This is stronger than attributing a cause from a destructor stack. It does not identify the precise missing cache-invalidation instruction inside Valve's closed binaries; Valve private PDB/source was unavailable, and export-only Steam/engine stack names must not be treated as exact internal function identities.

### Debugger effects and interruption

CDB x86 10.0.29680.1004 was attached only to receipt/path/creation-time matching private PIDs. `-G` releases the process-exit debug event. Live capture records `.exr -1`, registers, all-thread stacks and modules, then `gn`; full dump, `.ecxr`, disassembly and `!analyze -v` are separated from symbol downloads/offline analysis. Microsoft documents the distinct first/second chance command hooks in [SX exception controls](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/sx--sxd--sxe--sxi--sxn--sxr--sx---set-exceptions-).

Attaching at startup makes Steam show duplicate WebUI registration assertions during map reinitialization. A11, attached after map, instead pauses on an illegal-worker-termination assertion during teardown. Those modal waits are not clean exits. In F11 the agent selected Retry on the first WebUI assertion, then work was interrupted at the second; the user confirmed no interaction. Its subsequent resume/exit trigger is unknown. In A11 the agent selected Retry on the recorded worker assertion; A12 selected Ignore on a recorded WebUI assertion, disabling assert dialogs only for that process. None of these choices is represented as an uninstrumented success. A12 still reaches an actual final AV. The private sidecar records the interventions.

The A11 original collector raised `Disconnect not confirmed` while DLL detach was paused. A supplemental matching process handle was acquired and retained until signaled completion, recording `0xc0000005`. Its older field `already_exited_at_attach=true` meant a requested exit status was available, **not** that teardown had finished. The corrected monitor uses `handle_signaled_at_attach`; the native DLL-detach regression verifies this distinction. A10 has no such retained result and remains unknown.

Separate PE32 debugger fixtures captured an unhandled execute AV and an intentionally supplied `0xc0000409` record with parameter 7. They validate the capture tool only. No new SRCDS fast-fail subcode was obtained and no synthetic subcode is assigned to a historical failure. No ASan coverage of SRCDS or its DLLs is claimed.

## Active profiles, detours and scope

F13 uses the normal production DLL and the real-human public consumer: fake=0, supported=1, profiles=1 were observed for 120ms/0% Bernoulli, 120ms/10% Bernoulli, 120ms/10% GE, 0ms/100% GE, then reset. Before each of three verified unload/reloads it applies 5000ms latency and waits two seconds, so traffic is queued rather than merely configuring an unused profile. It repeats that queue setup before map change and before a real-client kick. Normal debug traffic includes `lag=5000.0ms loss=0% queued=1 reason=lag_queue newdata=1`. F12 follows equivalent commands with zero lag/loss.

After kick, each control verifies zero humans and the API reports zero profiles. The empty server may reset to `c1m1_hotel`; the client reconnects to a new authenticated session and gameplay is observed again. F13 applies 120ms/0% before the final 15-second interval and quits while the human remains connected. Both F12 and F13 exit 0 with matching Python/Win32 codes and signaled handles. In F13 immediately before quit, both FillServerInfo and NET_LagPacket have E9 entries targeting committed executable regions. F12 retains Left4DHooks' Fill E9 while NET_LagPacket is original with zero profiles.

During every CF unload, the module is verified absent, NET_LagPacket begins `55 8b ec 51 57`, and the Left4DHooks Fill entry is unchanged. Reloaded modules/code snapshots retain ASLR bases and executable target protections in the JSON. No bytes were manually restored and the validator was not widened. Queued traffic is evidenced by the production debug output; this investigation did not add a queue-introspection native or claim an independently sampled byte count after every cleanup.

These are 45 fresh recorded trials: 35 baseline plus 10 extended/diagnostic trials. A10 remains an unknown exit; A11's final code is supplemental rather than silently replacing its collector error. Three excluded setup pilots are not part of those 45. Extended profiles are staged comparisons, with one completed active sequence and one no-profile sequence under LAN 0; they do not establish a statistical failure rate or exhaustive independent per-factor coverage. The optional old player_fakelag/BuiltinVotes sequence was unnecessary to reproduce the minimum and was not run. No regression result here replaces the previous 289 API/39 SDK functional checks, or claims new CI approval.

## Reproduction, tools and remaining attribution

Use a new private trial for each observation. Keep the exact engine/server/runtime hashes above, SteamAppId 550 and the official dedicated steamclient. Set **only the private** server.cfg LAN value to 1 for reproduction, or 0 for the intervention; keep an exact byte backup for restoration. Start:

```powershell
& scripts/start-windows-shutdown-trial.ps1 -Row A -Scenario detached -Repeat <unused-number>
```

Connect the real Steam client to the private port shown by the launcher. After playable `c1m1_hotel`, append `sv_lan`, `@wait 5`, `changelevel c1m2_streets`, `@wait 10`, `sv_lan`, `status` to the returned command file. After playable streets and one jump, append `@run`. The controller validates authentication, observes 15 seconds, kicks the actual human and only sends quit if zero humans are confirmed. In the LAN-1 failure it can exit before quit. Never reuse a trial identifier or overwrite a dump.

For F controls, `tests/windows_shutdown_sequence.py` prints each manual-gated phase (`initial`, `after-map`, `after-reconnect`). `--profile` enables the staged public-API profiles; omit it for the control. Do not append the next phase until the client is visibly in the relevant playable session. `@reload_cf` verifies actual unload/byte restoration before reload. The sequence does not drive the client UI or bypass authentication.

For observation before map, create a context snapshot with `tests/windows_shutdown_context.py`, then attach `scripts/capture-windows-shutdown.ps1 -TrialState ... -PrivateDirectory ... -TraceFirstChance -ContextSnapshot ...`. A context must be fresh, PID/hash matched and point to live Steam vtables; an early all-zero context is refused. Omitting ContextSnapshot gives exception capture without write watches. Attach after map to avoid the startup WebUI assert perturbation, while noting that this cannot observe earlier invalidation. Dumps remain outside Git/OneDrive. Analyze with `scripts/analyze-windows-shutdown.ps1 -Dump ...` after exit. `tests/windows_shutdown_exit_monitor.py` can retain a receipt-matching supplemental handle if a collector has already returned an error during a modal wait.

`scripts/test-windows-shutdown-collection.ps1 -PrivateDirectory <new-private-folder>` builds the native detach fixture with MSVC x86 and runs all six collection regressions. The exporter privacy regression and Python/PowerShell syntax checks passed. Both SourcePawn consumers recompiled successfully with SourcePawn 1.12.0.7260; these fresh compiler outputs did not replace the fixed binaries used by the completed trials. Production source and DLL remained unchanged.

The current minimum demonstrates an engine/Steam lifetime failure enabled by LAN configuration, independently of the plugins. It excludes Custom-Fakelag, Left4DHooks, DHooks and SourceMod as necessary components for **this reproduction**. It does not prove the absence of a separate interaction bug or explain the missing historical `0xc0000409` subcode. Matching the old SM destructor to F11 identifies a detection point, not the original corruptor.

The concrete historical blocker is loss of the old dumps and exact allocation/context state during the user's prior authorized cleanup; retained text cannot recover the fast-fail parameters. For the remaining binary-level ownership question, matching Valve private engine/server/Steam symbols or source is unavailable. The exact next experiment is a fresh vanilla LAN-1 run with the A12 three watches, plus logged entry/return observations of `SteamGameServer_Shutdown` and `SteamInternal_GameServer_Init`; sample context +4/+8 and their first words immediately before shutdown and immediately after reinitialization, then repeat the same with LAN 0. Preserve the first exception and final event separately. A future authorized fix investigation should refresh/invalidate the owning Steam API context across that lifecycle and repeat the LAN-1 reproduction, then reintroduce the old behavior. That code intervention is proposed, not implemented here; changing CF's engine validator or hiding a teardown AV would not address the observed stale object.

## Restoration and delivery

The owned server and CDB processes are stopped. The exact original private server.cfg bytes are restored (including LAN 1); the tested LAN-0 intervention is **not deployed**. HKCU SteamClientDll matches the initial value. The normal CF DLL remains installed with the fixed SHA-256 above. All plugins remain under disabled and there are no active extension autoload markers. Optional recovered dependencies and the two temporary autoload markers are archived under private evidence.

The private server was rebuilt for this task; there was no pre-existing full per-file private-server backup. The full addons/cfg manifest was captured after the 35-trial matrix, not before the task. Comparison against that later inventory finds no modified non-runtime files after restoration. Deliberate differences are two archived autoload markers and Left4DHooks' generated ASLR-specific `left4dhooks.temp.txt`, archived instead of restoring stale process addresses. SourceMod data/logs and all private evidence remain. This is an explicit restoration limit, not a claim of byte-for-byte restoration of every generated cache.

Critical engine, steam_api and server hashes agree across the private copy, Steam game and Steam dedicated installations. No file writes were made to the two Steam installations, and no firewall/router/credential settings were changed. This is a critical-file verification, not a complete initial/final hash audit of both games. The game assets continue to be reused through SearchPaths.

The dated runtime JSON contains one entry for each trial, module/code snapshots, public numeric observations, separated exit-code fields, curated captured-exception records and private dump path/hash references. Null collector/debugger exit fields mean not independently retained. Raw console snapshots can repeat earlier numeric observations; their array length is not an API-call count. The separate evidence JSON contains read-only context snapshots and restoration checks. No dump, Valve DLL, client identity, player name, WAN or credential is included. The local private evidence root is `work/shutdown-private` beside the checkout.

The final commit is recorded externally in `REVISION_FINAL.json`, avoiding a self-referential commit hash. The delivery includes verified incremental bundle/patches above base `65031fb83da9b1ce9487237c3a19e83735c02686`, scripts, report, sanitized logs and SHA-256 manifest. There is no push, PR, deployment or product-code change.
