#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; Explorer, reporting for Explorer.
;
; Its own process, and that is the point. Explorer cannot report for itself the
; way vim can, so something has to do it on Explorer's behalf - but that
; something is a peer of vim, not part of the focus watcher. Living inside the
; watcher gave it a standing no other tool has: the watcher knew what an
; Explorer window was, and so decided which windows counted.
;
; Nothing here is privileged. It works out what folder the focused Explorer
; window is showing and posts events on the same endpoint with the same token as
; everything else. If it is not running, Explorer simply reports nothing, exactly
; as an app that has no reporter yet.
;
; It reads the FOCUSED window only, which is both cheaper and the right scope -
; see GlucExplorerScan. An elevated caller cannot do this at all, which is why
; this runs unelevated and why the hotkey script had to stop trying.

#Include gluc-http.ahk

global GLUC_EXPLORER_LAST := Map()
global GLUC_SHELL := 0

GlucExplorerStart()

GlucExplorerStart()
{
    SetTimer(GlucExplorerScan, 400)
    GlucExplorerTrayInit()
}

; The Shell, once.
;
; This used to be `ComObject("Shell.Application")` inside the scan, so a COM
; object was created and thrown away two and a half times a second. Measured at
; about 1.1ms of the 2ms each scan cost with no windows open at all - more than
; half the work was constructing the thing that does the work.
;
; Held in a global rather than re-fetched. If it ever goes bad the scan clears it
; and the next tick builds a new one, which is the same recovery the old code got
; by accident from doing it every time.
GlucShell()
{
    global GLUC_SHELL
    if (GLUC_SHELL)
        return GLUC_SHELL
    try
        GLUC_SHELL := ComObject("Shell.Application")
    catch as e
    {
        GlucExplorerTip("Shell COM unavailable - " e.Message)
        return 0
    }
    return GLUC_SHELL
}

; Only while an Explorer window is in front, and only that window.
;
; This walked every Explorer window every 400ms and read each one's folder over
; COM - a cross-process call per window, forever, whether or not anything was
; looking at Explorer. heat.md is explicit that producers report TRANSITIONS and
; not samples, and a poll of everything is the definition of a sample.
;
; What makes the narrow version correct rather than merely cheaper: the only
; consumer of an explorer select is focus-project, which wants the folder of the
; window that HAS FOCUS. A folder changing in a background window cannot affect
; that answer - and the moment you bring that window forward, this scan reads it,
; because then it is the foreground one. Nothing is lost that anything asks for.
;
; So the common case is one WinActive call and no COM at all, because most of the
; time you are not in Explorer.
GlucExplorerScan()
{
    global GLUC_EXPLORER_LAST, GLUC_SHELL

    ; Cheap, and it is the whole optimisation. CabinetWClass is a File Explorer
    ; window; the desktop and everything else is not.
    if (!WinActive("ahk_class CabinetWClass"))
        return

    front := WinExist("A")
    if (!front)
        return

    shell := GlucShell()
    if (!shell)
        return

    path := ""
    try
    {
        for window in shell.Windows
        {
            if (window.HWND != front)
                continue
            raw := window.Document.Folder.Self.Path
            if (GlucIsFilesystemPath(raw))
                path := GlucNormalizePath(raw)
            break
        }
    }
    catch as e
    {
        ; A stale Shell object throws here. Drop it so the next tick rebuilds.
        GLUC_SHELL := 0
        GlucExplorerTip("Shell COM failed - " e.Message)
        return
    }

    if (path = "")
        return

    ; Only when it changes. A window sitting in one folder is not news.
    if (GLUC_EXPLORER_LAST.Has(front) && GLUC_EXPLORER_LAST[front] = path)
        return

    GLUC_EXPLORER_LAST[front] := path

    reply := GlucSend("event", GlucEventJson("select", "explorer", GlucWindowJson(front), path))
    if (GlucLastError = "")
        GlucExplorerTip(path)
    else
        GlucExplorerTip("host not reachable`n" GlucLastError)
}

GlucIsFilesystemPath(p)
{
    if (p = "")
        return false
    if (RegExMatch(p, "^[A-Za-z]:[\\/]"))
        return true
    if (SubStr(p, 1, 2) = "\\")
        return true
    return false
}

GlucNormalizePath(p)
{
    p := StrReplace(p, "\", "/")
    if (SubStr(p, -1) = "/" && StrLen(p) > 3)
        p := SubStr(p, 1, StrLen(p) - 1)
    return p
}

GlucExplorerTip(text)
{
    A_IconTip := "gluc explorer`n" text
}

GlucExplorerTrayInit()
{
    A_IconTip := "gluc explorer - nothing reported yet"
}
