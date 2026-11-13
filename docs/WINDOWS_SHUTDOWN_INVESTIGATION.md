# Windows SRCDS shutdown investigation

Status: investigation in progress. No cause is confirmed and the historical shutdown failures are not resolved by the successful trials collected so far. The functional acceptance from the previous load-order investigation remains a separate result.

## Scope and fixed inputs

Production base: `65031fb83da9b1ce9487237c3a19e83735c02686`; production DLL source: `9c7debcf334ef534d715449b828e0c6d5fa67853`. Only investigative tools and documentation change on `codex/windows-shutdown-investigation`. There is no product fix, deployment, push or PR.

The normal PE32 DLL SHA-256 is `3e062b7047baad8551c5bd384fa18f9727735418ad917f60a04d155589165a73`; engine SHA-256 is `8a6d468059394bf4cfce32f11dcba12ef45de88da1373084d5a2916d0bf7ba86`. SourceMod/DHooks 1.12.0.7260, Metamod 1.12.0-dev+1229, Left4DHooks 1.175 from `7672bdefc4e03a693ae7fdc06e470df41b4cc069`.

The private server uses copied core executables and writable game/configuration directories. Absolute SearchPaths reuse the official dedicated installation's game assets. Neither a complete duplicate game nor writable hardlinks are used. The desktop Steam client and both installed games are preserved. SteamAppId is 550; SteamGameId/overlay metadata is 222860. The official dedicated `bin/steamclient.dll` is selected briefly through HKCU, verified in the server's actual modules and restored in `finally` before client connection. No Steam restart occurs in this window.

## Protocol and tools

Each row is a fresh owned process on `c1m1_hotel`, with the same authenticated real Steam client. After observing the playable map and issuing one jump input, the controller checks one human, resolved Steam identity and the server's authentication event. It then records 15 seconds with the human remaining connected and sends `quit` from the private console. This is a short playable network session, not an extended campaign stress test. Loading and authentication time precede the defined interval and vary between trials.

`scripts/start-windows-shutdown-trial.ps1` starts one row; `tests/windows_shutdown_trial.py` validates loaded components and detour bytes before accepting it. Append `@run` to the trial's initially empty command file only after the real client reaches gameplay. The `connected`, `detached` and `idle` scenarios are distinct. Detached uses the authenticated human's `kickid`, verifies zero humans, then quits. Idle requires zero humans throughout.

The controller holds the actual child process handle through shutdown, waits up to 90 seconds and cross-checks Python's exit code with Win32 GetExitCodeProcess and a signaled process handle. A timeout or collector error leaves the process explicitly alive, never labelled a clean shutdown. No forced termination is used to manufacture success. The collector regression uses real fixture processes returning 0, 23, `0xc0000005` and `0xc0000409`, plus an unsignaled timeout case; all five passed. The previous adopted-process helper also returned the correct codes in these fixtures, so this test does not establish a defect in the old collector.

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

Previously reported real-client exits were `0xc0000409` (Left4DHooks first, PID 10216) and `0xc0000005` (reverse order, PID 21292); earlier vanilla also had `0xc0000409`. New idle references from the prior task exited 0. The old process dumps were removed during the user's explicitly authorized cleanup before this assignment; retained textual traces cannot recover their missing object memory or fast-fail parameters.

An older textual live-debug trace reports a first-chance read AV at `server.dll+0x1e121d`, address `0x28`. The debugger was subsequently quit, so this is not by itself proof of the final unhandled exception. Another retained shutdown minidump analysis reports `sourcemod.2.l4d2.dll+0x13b63`, reading `[ecx+4]` with ECX zero during loader shutdown. Detection in that destructor does not identify the writer or original invalidation. Neither trace establishes Custom-Fakelag as the cause.

The new private instance was reconstructed after cleanup. Its minimal component set, fresh process sequence and copied writable layout differ from the former long API/reload/map-change sessions. Absence of failure in the short baseline cannot rule out those sequences or runtime lifecycle effects.

## Pending work

Complete all three alternated human repetitions per row, fresh disconnected-client controls and no-client references. Then reproduce the old longer sequence with one additional factor at a time, retaining matched no-profile controls. Any debugger rerun must follow an uninstrumented reproduction and use only the owned server PID. `scripts/capture-windows-shutdown.ps1` is an opt-in CDB attachment tool under validation, not evidence of a completed debugger trial. Final results, causal assessment, precise next experiment and restoration evidence will replace this pending status before delivery.
