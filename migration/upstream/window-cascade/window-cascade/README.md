# Window Cascade internals

launch `../window-cascade.ahk`, not the files in this directory. the launcher owns the process, icon, logging setup, startup sequence, registered command handler, and exit callback. these files are explicitly included into that same AutoHotkey v2 script. they are not separate running scripts or independently reusable libraries.

Window Cascade uses the shared Keybindings library and an optional Caps + Pause Layers service. Window management works without a running layer service; ordinary shortcuts can be assigned through the tray menu. The legacy `capslock-layer.ahk` interface is no longer used.

## where to make changes

| file | responsibility |
| --- | --- |
| `settings.ahk` | defaults, persisted rotate-key and focus-tab color selections, shared runtime state, debug settings, and CapsLock Layer command IDs. |
| `controls.ahk` | focus-tab mouse bindings, ordinary desktop-click handling, Explorer Space re-show intent observation, required CapsLock Layer presence/watch logic, and registered-message dispatch. |
| `discovery.ahk` | desktop monitor hints, the startup window snapshot, discovery polling, placement queueing, Windows event hooks, and destroyed-window cleanup. |
| `window-drag.ahk` | native mouse-drag tracking, release-time snap/adopt/release decisions, and deferred-layout recovery. |
| `layout.ahk` | managed history, canonical slot geometry, occupancy, stacks, exposed layers, compaction, and Z-order sorting. |
| `navigation.ahk` | focusing, guarded new-window foreground recovery, swapping, slot/layer rotation, spatial navigation, and bringing a cascade forward. |
| `placement.ahk` | explicit placement, identity-checked readiness retries, new-window placement, and bounded asynchronous stabilization. |
| `commands.ahk` | adoption and one-shot adoption undo, gathering, cross-monitor moves, monitor-wide close commands, restore settling, and membership cleanup. |
| `suspension.ahk` | Caps + M minimize/restore ownership and Caps + P automatic new-window placement admission state. |
| `focus-corners.ahk` | one visible tab per slot, overlay lifetime and position, representative handoff, and active-slot coloring. |
| `focus-tab-clicks.ahk` | instant press-to-focus/cycle, live target validation, mouse-release pairing, and missed-release recovery. |
| `windows.ahk` | window filtering, visible/raw frame geometry, monitor lookup, and monitor-selection policy. |
| `dpi.ahk` | scoped physical-pixel API calls, per-monitor DPI probes, and display snapshots. |
| `display.ahk` | coalesced live display refresh, runtime slot preservation, and deferred geometry updates without reload. |
| `interface.ahk` | tray menu, help and its custom icon, startup shortcut, rotate-key and focus-tab color persistence, and compatibility checks. |
| `debug.ahk` | logging, log-reset messages, error reporting, and diagnostic window descriptions. |

## initialization and dependencies

only `settings.ahk` contains top-level state initialization. the launcher includes it before building the tray menu, registering the command handler, seeding existing windows, installing window hooks, and starting timers.

the remaining modules primarily contain function definitions and event/message entry points. all includes are explicit in the launcher; modules do not include each other. the launcher anchors include paths to `A_ScriptDir` so they do not depend on the shell's current directory.

keyboard shortcuts are registered by the Keybindings library, and action events dispatch locally to Window Cascade. Caps/Pause chords are delivered through the optional service.

## integration contracts and paths

`window-cascade/keybindings.ahk` maps action IDs and first-run defaults onto the
existing window-management dispatcher. `lib/keybindings.ahk` provides persistent
configuration, conflict checks and the configuration UI. The optional
`lib/caps-pause-client.ahk` connects to the independent layer service.

The original `RotateKey` setting is read once as the first-run default for the
two rotation actions. After that, edit their bindings in Keybindings. The legacy
rotation submenu and cross-process command messages are no longer used.

The launcher and icon retain their paths. Window Cascade settings/logs remain
under `%LOCALAPPDATA%\Window Cascade`; Keybindings configuration is kept
separately under `%LOCALAPPDATA%\nroj\AutoHotkey\keybindings-v1`.

With the layer service offline, the window hooks, drag placement, focus tabs,
tray commands and any configured ordinary hotkeys remain available.

## focus-tab clicks

each monitor/slot shows at most one focus tab. an inactive slot represents its exposed window; the active slot represents the next layer below the foreground window. a focused single-layer slot has no tab. deeper layers remain managed but their tabs stay hidden, so opacity no longer indicates stack depth. the full-height marker follows the highest slot regardless of which layer represents it.

pressing an inactive slot's tab focuses its exposed window immediately. pressing the active slot's tab rotates within the foreground window's current native Z-order band and focuses the next layer in that band. repeated clicks visit every layer in order when the stack is all-normal or all-topmost. in a mixed stack, always-on-top windows remain in the topmost band instead of being silently demoted, so normal layers remain behind that band.

all actions happen once on mouse-down. the pressed tab is hidden immediately; the renderer selects the new representative without waiting for mouse-up. holding, dragging, and releasing add no action. there is no swipe preview, temporary opacity/topmost override, or focus-tab Escape binding. mouse and keyboard layer rotation use the same native Z-order-band rule.

the renderer hides the old representative before showing its replacement. geometry queries stay interruptible; the selection and hide/show handoff run together, and stale foreground or click-generation snapshots are retried.

`controls.ahk` pairs mouse-down and mouse-up through AutoHotkey's mouse hook. hit-testing captures the overlay, target HWND, and foreground HWND before the press handler resolves live slot membership. stale targets are skipped rather than retargeted. even a skipped click owns its matching release outside the tab or after its target closes; ordinary application clicks and drags retain their native behavior. `focus_tab_release_poll_ms` controls a temporary missed-release guard that only clears mouse ownership and never performs a focus/cycle action. reload/exit stops that guard.

focus-tab colors are selected separately for the active and inactive slots from the tray. the selections persist under `[FocusTabs]` in `%LOCALAPPDATA%\Window Cascade\settings.ini`; defaults are Green for the active slot and Grey for inactive slots.

### appearance diagnostics

focus-tab GUIs are created per-monitor DPI-aware with `-DPIScale`. their anchor coordinates and full-height bounds use physical pixels; thickness, overlap, and short-marker height are 96-DPI UI dimensions scaled once for the target monitor. cloaked target windows are excluded from rendering and live click activation, without discarding their managed membership. an overlay pass with no visible slot candidates skips the global Z-order enumeration.

normal tab rendering changes native opacity only when the desired value changes and repaints changed or newly shown overlays. the opacity cache is updated only after a successful native operation. overlay operations use pure HWNDs so hidden-window lookup does not depend on `DetectHiddenWindows`. the configured opacity values remain unchanged, and deeper tabs do not contribute additional opacity.

**Verbose debug logging** in the tray toggles `debug_verbose_enabled` for the current run only and defaults to off after every restart. when verbose logging is enabled, `Focus-tab appearance.` entries are written only when the observed state changes. they include the active window, active-slot window count, click ownership, tab role, color, cached base alpha, native alpha, visibility, topmost state, Z-order predecessor, and rectangle. clicks do not override opacity. compare entries from a faint and a clear state when investigating intermittent appearance changes.

## minimize, restore and automatic cascading

`Caps + M` is a pure minimize/restore toggle for **managed windows on all monitors**. the first press snapshots the currently visible managed windows and minimizes only that saved HWND/PID set. Window Cascade otherwise keeps running normally: new windows can still be placed, focus tabs remain available for visible members, drag/drop snapping stays active, and ordinary cascade commands continue to work.

the next `Caps + M` restores only still-minimized windows from that saved set, in saved Z-order. independently minimized windows are never added to the set. closing a saved window or manually restoring it relinquishes Window Cascade's restore ownership. windows opened after the minimize action are not part of that restore and stay exactly where normal cascading placed them. after restore, the saved set is cleared and the next press takes a fresh snapshot.

`Caps + P` pauses/resumes **automatic cascading of newly opened windows only**. existing managed windows remain fully active: focus tabs, drag/drop snapping, compaction, placement recovery, `Caps + M`, navigation, rotation, gathering, closing, adoption, and debug commands continue to work normally. windows first opened while automatic cascading is paused stay unmanaged and are not retroactively adopted when automatic cascading resumes; use `Caps + Insert` or drag/drop to adopt one explicitly.

pausing automatic cascading stops new automatic placement requests from being admitted. a placement already queued before the pause may finish normally. windows first discovered while paused are remembered as unmanaged. it does **not** suspend Window Cascade hotkeys, mouse bindings, focus tabs, timers, existing managed membership, or layout maintenance. the auto-cascading pause state is runtime-only and is not persisted.

`Caps + P` can be toggled without disturbing an active managed layout. reload/exit still restores any still-minimized windows owned by `Caps + M` before discarding its in-memory restore set, without recascading unrelated windows.

### restore settling and compaction

the shared restore path registers all saved targets across monitors before sending any restore requests. membership is protected and compaction is deferred while the requests run and the restored windows settle. the existing watcher checks normal/visible state, actual slot proximity, and unchanged native/DWM rectangles, then queues compaction from current membership rather than replaying an old layout. `cascade_restore_poll_ms`, `cascade_restore_settle_ms`, and `cascade_restore_timeout_ms` remain 50, 200, and 5000 ms.

closed, moved-out, re-minimized, or manually dragged targets stop holding a restore batch. the timeout releases the compaction gate instead of leaving a failed restore permanently blocking a monitor. the discovery fallback still reconciles missed restore notifications when enabled. drop-slot preferences and the shared drag/drop tolerance remain unchanged.

## scoped close batching

`Caps + F4` closes all **visible, non-minimized** managed layers on the command monitor. hidden, cloaked, and minimized members stay managed and are excluded from the close batch, including windows currently owned by the `Caps + M` restore set. the eligible HWND/PID scope is registered before any `WinClose` requests. destroy events remove windows from that batch, while layout compaction for the affected monitor stays deferred. the final destroyed target releases the batch and allows one queued compaction, so the cascade does not repeatedly reflow between individual closes.

if a close is cancelled, ignored, or fails, `cascade_close_timeout_ms` releases the remaining batch after 5000 ms from the end of request dispatch. this is only a compaction grace period: it never dismisses a save prompt, retries the close, or kills an application. a still-open save prompt does not keep compaction blocked indefinitely. stale expiration callbacks cannot clear a newer batch. an interrupted close loop also stops if a newer batch takes ownership.

`Caps + F7` gathers the other monitors' cascades onto the command monitor. the former `Caps + Alt + F7` modifier is removed; the plain command is also available through the one-shot Caps layer.

## window drag and drop

`cascade_slot_tolerance` is the single membership/drop tolerance, defaulting to 56 screen-coordinate pixels on each axis. the old separate release tolerance is removed. slot proximity is measured from the window's visible top-left corner, not the pointer. among eligible canonical positions, the nearest position by squared distance wins; equal distances prefer the earlier slot.

a native mouse drag preserves its starting cascade membership and logical slot until the move loop finishes and the mouse button is released. passing outside the tolerance while still holding does not remove the window. focus tabs for the dragged window are hidden, compaction is deferred, and old placement corrections are cancelled so they cannot fight the drag.

on release near a slot, the window snaps to that exact canonical position and the normal monitor-relative cascade size. this can move an existing member, re-adopt a released window, or adopt another eligible normal application window. the destination monitor must already have a visible cascade; the last managed window can also return to its own cascade. dropping elsewhere leaves the window unmanaged at the dropped position. ordinary clicks, content drags and edge resizes do not adopt windows; Escape retains native cancellation behavior.

a successful drop queues slot-preserving compaction on the affected cascades after the drag finishes. existing windows stay in their slots wherever possible; surplus background windows fill holes and balance the layers instead of the whole cascade being flattened and reassigned. the most recent dropped window has priority in the destination monitor's queued compaction, even if focus changes or compaction waits for a close batch. later manual drops and keyboard commands can still rearrange windows; this is not a permanent per-window pin.

with at least one full layer of managed windows, the dropped window stays in the selected slot. with fewer windows than slots, only the first N canonical positions are retained for N managed windows: a drop into that range stays there, while a drop beyond it moves inward to keep the cascade compact. minimized members still count toward that total and are not restored just to fill visible gaps. later compactions preserve each slot's front windows and move only surplus layers as needed.

placement correction follows each window's final destination. dropped-out windows stay known/handled, so merely focusing or showing them again does not auto-adopt them.

`Caps + Insert` remains available for explicit adoption and re-slotting, and newly opened windows still use normal automatic placement. global disable stops both automatic new-window placement and intentional cascade drag/drop. keyboard cascade commands are held off during a native move/resize interaction. the temporary drag watcher stops on completion, cancellation, destruction, or script exit.

## foreground recovery and performance

bringing a cascade forward preserves each window's pre-existing always-on-top setting; only temporarily promoted normal windows are returned to the normal Z-order band. swaps, layer rotation, and compaction also preserve that boundary: relative Z-order rebuilding occurs only between windows confirmed to be in the same band. if a native topmost-state query fails, that Z-order mutation is skipped rather than treating the window as normal; compaction does not spin on an immediate retry.

new-window placement remains non-activating. discovery retains focus context when a new window is already foreground or appears within `new_window_focus_timeout_ms` (3000 ms) of a taskbar mouse press. taskbar correlation is a recent-input heuristic, not proof of which process the taskbar launched. background launches without that context or observed foreground ownership are not activated.

existing managed windows that re-show the same HWND use a separate 1000 ms trusted-intent gate. taskbar re-shows retain the existing taskbar/monitor correlation and remain SHOW-driven. a plain, unmodified Space press in an active Explorer window also snapshots that Explorer HWND/PID and monitor; the first other-process managed HWND may bind from either SHOW or FOREGROUND, whichever arrives, but only if that target becomes foreground. a matching genuinely new HWND consumes the same intent when it enters the ordinary new-window path, so the short-lived hint cannot remain available for an unrelated handled re-show. the bound handled HWND makes a later duplicate signal harmless. modified/Caps Space presses, stale/recycled Explorer identities, competing handled events, and unrelated background re-shows do not retarget windows. on the same managed monitor, reconciliation compares the visible rectangle with the remembered logical slot and canonical size; already-correct windows are left untouched, while drifted windows are restored without changing membership/history order. on a different monitor, the ordinary destination-slot policy is used.

SHOW and FOREGROUND WinEvents can arrive in either order. a foreground event for a pending placement records ownership on that request and starts recovery immediately, without waiting for placement to finish. `context.recovery_started` prevents the later placement call from restarting recovery, including after user interaction has cancelled it. the watcher accepts the same live HWND/PID while it is pending placement or managed.

shell/taskbar launches that use the 300 ms startup-settle grace period get one provisional non-activating move as soon as the first readiness pass accepts the window. that move reserves the same monitor, slot and size used by the settled pass, so other launches see the slot as occupied and the final pass does not choose a different destination. the window is not added to cascade history until the settled placement succeeds. if early eligibility, geometry, display generation or the native move is unsafe, provisional placement is skipped and the existing settled path remains the fallback. if the provisional window still matches that destination within the normal stabilization tolerance when the settled pass runs, the redundant second `SetWindowPos` is skipped; any drift still takes the ordinary final move path.

the watcher polls at `new_window_focus_poll_ms` (100 ms). the shell-settle period is bounded by `new_window_shell_settle_ms` (5000 ms), measured from recovery start rather than added after the ordinary timeout. reclaiming focus during that period requires prior foreground ownership and a current shell/taskbar foreground window. switching to any real application, including the original launch source, cancels recovery. mouse clicks, Caps commands, window drags, focus-tab clicks, closed/minimized targets, and identity changes also cancel it. mouse buttons, Ctrl, Alt, and Win modifiers block activation attempts; Shift alone does not postpone recovery.

the shell-settle path tries `SetForegroundWindow` first. after three consecutive denials, it may call AutoHotkey's `WinActivate` once per request. ordinary attempts may continue until the settle deadline, but the stronger fallback is not repeated. `WinActivate` performs its own short retries and may synthesize Alt as part of its built-in workaround; it is not a modifier-free call. keep it in this guarded recovery path rather than adding startup key injection or relying on a close command to make later activation work. the script does not add input-queue attachment, fake focus messages, permanent topmost overrides, or foreground-lock registry changes. recovery logs report the attempted method and observed focus state, not a guarantee that Windows always permits activation.

`Caps + Delete` closes the active window with `WinClose("A")`, without sending Alt+F4. application-specific close handling still applies. a foreground target's stale marker is hidden immediately; the overlay renderer still selects the next layer's tab independently. an active-slot tab for a deeper layer remains intentional and does not by itself indicate failed focus.

ordinary lifecycle/error logging stays enabled and writes to `%LOCALAPPDATA%\Window Cascade\window-cascade-debug.log`. the active log rotates after crossing `debug_log_max_bytes` (2 MiB by default), with one `.old` backup; size is checked once at startup and only every `debug_log_size_check_interval` (128) writes afterward, not on every event, so the active file may exceed the threshold briefly between checks. `Caps + F5` clears both segments. focus recovery, placement, restore reconciliation, compaction, and destruction of pending/handled/managed windows remain visible in the normal log. **Verbose debug logging** in the tray toggles `debug_verbose_enabled` for the current run only and defaults to false after every restart; raw show/poll events, unrelated or repeated destroy events, and expensive title/appearance snapshots are opt-in. destruction is always processed even when its log entry is suppressed. foreground diagnostics retain the foreground HWND, thread-active HWND, keyboard-focus HWND/root, and process IDs, and skip native diagnostic queries when logging is disabled. the temporary placement `foreground-before` / `foreground-after` probes are removed.

`Caps + F5` clears the debug log and starts a fresh logged session. `Caps + F6` copies the current log to the clipboard as a Markdown code block without clearing it, activating or opening a window, cancelling focus recovery, or writing a capture entry into the log itself. a brief cursor-adjacent tooltip confirms success or failure without entering the debug history. a failed clipboard write is not retried from the error path, so clipboard contention cannot turn the observational command into another unhandled clipboard operation. this makes it possible to isolate a reproduction with F5, trigger it, then snapshot the untouched history with F6. both shortcuts are also available through the one-shot Caps layer.

`SetWinDelay 0` yields without AutoHotkey's default per-window 100 ms sleep; restore/placement watchers still decide readiness explicitly. a focus-tab pass uses one observed rectangle per candidate and one canonical geometry calculation per monitor. minimized overlays are cached/hidden rather than repeatedly destroyed, and unchanged opacity/Z-order operations are skipped. per-window placement requests retain object identity through retries so stale callbacks cannot target a later request for a recycled handle. placement confirmation stops after `placement_stabilize_confirmation_limit` (3) final checks instead of polling forever. no Windows desktop timing benchmark is implied by these source-level optimizations.

## physical pixels and live display changes

all monitor/work-area bounds, cursor positions, raw window rectangles, and external geometry changes use a short per-monitor DPI-aware context through `dpi.ahk`. DWM visible-frame bounds are already physical pixels. each wrapper restores the caller's previous DPI context in `finally`, including the native error code. this is not a process-wide awareness change: the normal help GUI stays system-DPI-aware. the DPI path requires Windows 10 version 1607 or later.

there are no per-percentage presets. window width/height remain the configured fraction of the physical work area. slot offsets, edge margins, minimum sizes, and the 56-pixel drop tolerance keep their existing physical-pixel meaning. only the focus-tab UI dimensions use `Round(value * dpi / 96)`. tab repaint caching includes DPI, even when the target rectangle has not changed.

a hidden, control-free per-monitor-aware probe on each monitor supplies that monitor's effective DPI. querying an external app's HWND directly would return 96 for an unaware app or the system DPI for a system-aware app, so it cannot reliably size our overlays. the same monitor-based reading distinguishes cross-DPI drag resizing from an ordinary edge resize. probes never adopt windows, receive focus deliberately, or appear in the taskbar.

`WM_DISPLAYCHANGE`, `WM_SETTINGCHANGE`, our own probes' `WM_DPICHANGED`, and resume notifications coalesce a refresh. messages sent to foreign applications are not received through our `OnMessage` handlers. the existing one-second discovery fallback checks the monitor snapshot too; there is no additional permanent fast display timer. live monitor checks before membership pruning also protect against a late notification.

**changing display scaling does not reload Window Cascade.** a DPI-only refresh leaves the history map and its arrays in place. a runtime HWND/PID slot record remembers each member's last intended slot while Windows is resizing applications. affected visible normal windows are moved asynchronously with no activation or Z-order change. minimized, hidden, or cloaked members retain their destination until they become visible again; the script does not restore them just to update geometry. pausing automatic new-window cascading does not defer reflow for existing managed windows; the independent Caps + M restore set is retained. drags and unfinished focus-tab clicks also defer reflow, and manual dragging takes ownership of its target.

monitor indices are remapped using the display device names in the current session. if a display disappears, its managed members use the current primary display; if fewer canonical slots fit, an old slot is clamped to the last available slot. this is not persistent monitor/EDID matching, and reconnecting a display does not automatically send windows back to their former screen. stale monitor-index batch gates are cleared on a topology remap, not on an ordinary DPI-only refresh.

cross-DPI placement can still be followed by the target application's own DPI resize. the existing generation-checked stabilization path permits up to three prompt corrections, then returns to its original bounded backoff. a DPI transfer needs a second matching check before its reservation is released. display changes invalidate superseded corrections and pending new-window requests resolve their saved monitor device again. no state is written to disk to support this behavior.

## checking a change

from the repository root, run:

````powershell
./validate.ps1
````

this validates the root scripts and their include trees. do not validate or launch the module files separately.

Window Cascade seeds windows already open at startup for discovery but does not automatically adopt them into the managed cascade. test placement with newly opened windows or explicitly adopt an existing window.

for Window Cascade changes, check:

- new-window placement and delayed window startup; duplicate discovery and cancelled/recycled-HWND retries
- shell/taskbar launches: provisional placement should reach the final reserved slot before the 300 ms settle pass, with no second slot jump; failed or late readiness must fall back cleanly
- handled-window re-shows: use PowerToys Peek or another reusable preview/tray window as a test; exercise both SHOW and foreground-only re-shows, same-monitor drift must recover the remembered slot/size, already-correct same-monitor re-shows must not issue another move, cross-monitor re-shows must follow the trusted intent, a fresh-process/new-HWND preview must consume the Explorer Space hint through normal placement, and modified/Caps Space or unrelated background events must not retarget
- minimize with Caps + M, launch one to three windows, and verify normal automatic placement and cascade drag snapping continue
- Shift + taskbar launch: keep Shift held for several seconds, verify the new window remains typeable and its single-layer tab stays hidden; switching/clicking elsewhere must cancel recovery
- fresh-process focus recovery: reload Window Cascade, test the first launch before using any close command, then repeat after both Alt + F4 and Caps + Delete
- deny/delay activation and inspect the foreground diagnostic; background launches must not steal focus
- focus tabs: at most one visible tab per monitor/slot, correct exposed/next-layer target, and stable opacity across stack depths
- focus-tab clicks: inactive slots focus without rotation; repeated active-slot clicks visit all layers in a three-or-more-window stack
- focus-tab handoff: no overlapping replacement, immediate single-layer tab disappearance, and full-height marker preserved after rotation
- holding/dragging/releasing: no preview or repeat action; release outside the tab or on another monitor is still consumed
- ordinary app clicks/drags and Escape retain native behavior; also test close/minimize/move, focus changes, and reload/exit while holding
- slot swaps, slot/layer rotation, and exposed-stack ordering
- test mixed normal/always-on-top stacks through bring-forward, slot swaps, forward/reverse layer rotation, focus-tab clicks, and compaction; existing topmost windows must remain topmost, normal windows must remain normal, and both rotation directions must stay within the front window's native Z-order band
- force/reproduce a failed topmost-state query during compaction: geometry may still compact, Z-order rebuilding for that stack must be skipped, and no repeated 120 ms compaction loop should result
- queue a cascade command behind a slow command, then change/close the foreground window: the delayed command must be discarded unless its original HWND and PID still own foreground
- Caps + F4: only visible, non-minimized layers on the current monitor close without intermediate compaction; hidden, cloaked, minimized, and other-monitor members stay untouched
- drop-slot preservation: exactly one full layer and multiple layers; other windows fill gaps without moving the dropped window
- partial layer: drops within the first N slots stay put; drops beyond that range compact inward
- deferred drops: change focus, close other windows, or finish a close batch before compaction; minimized members stay hidden
- mouse drops: 14/15/55/56 px offsets all snap with the same tolerance; outside every slot releases only on mouse-up
- drag away and back while still held; drag to another slot/monitor; no mid-drag pruning, reflow, or corrective move
- adopt an unmanaged window by dropping near an existing cascade; outside/empty-monitor drops remain unmanaged
- cancelled drags, edge resizing, rapid successive drags, target closure, and delayed new-window placement during a drag
- after mouse release, simulate/observe a failed native move-state query: snapping must be abandoned after `cascade_drag_unknown_release_timeout_ms`, the drag gate must clear, and later cascade commands must work normally
- Caps + M across multiple monitors: only windows minimized by that press are restored; independently minimized windows stay hidden
- after Caps + M, open new managed windows, then press Caps + M again: only the original saved set restores and the newer windows stay where Cascade placed them
- close or manually restore a Caps + M-saved window before the second press; it must not be revived/re-restored
- slow restores, rapid re-minimize, drag during restore, and close-batch deferral: no lost membership or permanent compaction lock
- missed restore notifications and interrupted queued work: the existing slow fallback recovers the pending merge
- unchanged layouts/tabs should not keep issuing opacity writes or restarting placement corrections
- adoption and the one-shot adoption undo path
- Caps + F7 gathering and cross-monitor moves
- while automatic cascading is paused: open new windows and verify they stay unmanaged while Caps + M, navigation, rotation, F4/F5/F6/F7, focus tabs, and drag/drop continue to work normally
- Caps + P pauses/resumes automatic placement only; a placement already queued before the pause may finish, pause-time windows remain unmanaged after resume, and newly discovered windows after resume auto-cascade normally
- tray help displays icons/window-cascade.ico in its caption/Alt+Tab; Escape and the hotkey both close it without leaking icon handles
- tray Pause auto cascading mirrors Caps + P; rotate-key and focus-tab color preferences remain available while auto cascading is paused
- required CapsLock Layer behavior during startup, quick reloads, and a sustained dependency loss
- cancel a save prompt after Caps + F4; verify compaction resumes after the close grace period without forcing the window closed
- overlap close attempts; an older expiration must not release a newer batch or retain an old gate
- switch virtual desktops; hidden/cloaked targets must not leave clickable tabs behind
- test 100/100, 100/125, and 100/150 monitor pairs: first-window centering, physical 80% sizing, tab alignment, click targets, and cross-monitor keyboard moves/drops
- launch an app on the 100% display and let Cascade place it on the 125%/150% display; test the reverse direction too, including an app that scales itself after the move
- change scaling live with existing multi-layer cascades, without reloading; membership, slots, focus, and internal Z-order should survive once the transition settles
- repeat a live scaling change with an independently minimized member, with a Caps + M saved set, and while automatic cascading is paused; existing managed windows should still reflow normally and minimized members must not be restored merely to update geometry
- change resolution or disconnect a display; check the documented primary-display fallback and slot clamping, then verify fresh launches still work
- grow or seed the debug log beyond `debug_log_max_bytes`, then start/write again: the old active segment must become `.old`, logging must continue in a fresh active file, and repeated rotation must retain only one backup
- Caps + F5 after rotation must remove both the active log and `.old` before starting the fresh reset session
- Caps + F6 with normal clipboard access and with clipboard access deliberately unavailable: success copies the untouched active log, failure shows only the failure tooltip and does not throw or append to the log
- change Space/Tab from the Cascade tray with the Caps help GUI open, then reload Caps; the selection must stay synchronized
- hold Caps + Q, add W, release Q while holding W: F13 must release independently of F14; also release Caps first and reload while held
- tap Caps, hold Q, then press W: only Q consumes the one-shot; W stays ordinary and Q does not leak repeat characters
- type uppercase letters using separate left-Shift presses; ordinary shifted typing must not toggle Caps Lock, while a bare double-tap still does
- re-arm Caps while an older consumed key is held; releasing the old key must not cancel the new one-shot
- start a Terminal copy/clear chord, switch apps before releasing it, and verify the new app receives no macro shortcuts
- test normal and failed Terminal copies; a failed copy restores the previous clipboard only while the script's cleared clipboard is unchanged

avoid close-scope tests with unsaved work. syntax validation does not replace Windows desktop behavior testing. wait for the validation process and inspect its actual exit code; a previously printed success line is not a substitute for loading the updated launcher.

## AutoHotkey documentation

- [Include semantics](https://www.autohotkey.com/docs/v2/lib/_Include.htm)
- [Script startup and validation switches](https://www.autohotkey.com/docs/v2/Scripts.htm)
- [WinActivate retries and modifier workaround](https://www.autohotkey.com/docs/v2/lib/WinActivate.htm)
- [WinClose behavior](https://www.autohotkey.com/docs/v2/lib/WinClose.htm)
- [AutoHotkey DPI contexts and GUI scaling](https://www.autohotkey.com/docs/v2/misc/DPIScaling.htm)
- [GetDpiForWindow awareness-dependent results](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiforwindow)
- [WM_DPICHANGED](https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged)
