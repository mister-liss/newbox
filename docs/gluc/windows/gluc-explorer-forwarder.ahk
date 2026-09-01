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
; Nothing here is privileged. It watches Explorer windows, works out what
; folder each is showing, and posts events on the same endpoint with the same
; token as everything else. If it is not running, Explorer simply reports
; nothing, exactly as an app that has no reporter yet.

#Include gluc-http.ahk

global GLUC_EXPLORER_LAST := Map()

GlucExplorerStart()

GlucExplorerStart()
{
    ; Foreground changes are the interesting moment, but a folder can also
    ; change under a window that never loses focus, so both.
    SetTimer(GlucExplorerScan, 400)
    GlucExplorerTrayInit()
}

GlucExplorerScan()
{
    global GLUC_EXPLORER_LAST
    try
        windows := ComObject("Shell.Application").Windows
    catch as e
    {
        GlucExplorerTip("Shell COM unavailable - " e.Message)
        return
    }

    live := Map()
    for window in windows
    {
        try
        {
            hwnd := window.HWND
            raw  := window.Document.Folder.Self.Path
        }
        catch
            continue

        if (!GlucIsFilesystemPath(raw))
            continue

        path := GlucNormalizePath(raw)
        live[hwnd] := path

        ; Only when it changes. A window sitting in one folder is not news.
        if (GLUC_EXPLORER_LAST.Has(hwnd) && GLUC_EXPLORER_LAST[hwnd] = path)
            continue

        reply := GlucSend("event", GlucEventJson("select", "explorer", GlucWindowJson(hwnd), path))
        if (GlucLastError = "")
            GlucExplorerTip(path)
        else
            GlucExplorerTip("host not reachable`n" GlucLastError)
    }

    GLUC_EXPLORER_LAST := live
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
