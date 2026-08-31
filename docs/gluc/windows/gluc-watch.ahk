#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; The focus watcher, deliberately a separate process from the hotkeys.
;
; It has to run unelevated. Reading another process's Explorer window over COM
; crosses an integrity boundary, and an elevated process is refused - so the
; watcher saw every Explorer window and could never read a path from one.
;
; The hotkeys have the opposite requirement: they run elevated so they still
; fire when an elevated window has focus. Two requirements that cannot both be
; met by one process, and two jobs that were never related anyway.

#Include gluc-http.ahk
#Include gluc-watch-core.ahk
#Include gluc-explorer.ahk
#Include gluc-terminal.ahk

GlucWatchStart()
