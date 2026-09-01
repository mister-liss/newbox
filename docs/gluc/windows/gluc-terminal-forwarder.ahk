#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; The terminal forwarder. A peer of the Explorer forwarder, and shaped the
; same way: watch a kind of window, work out what it is looking at, report it.
;
; Reads the window title, because PowerShell 7 sets the tab title to the
; current directory via OSC 9;9 and Windows Terminal mirrors the active tab
; into the window title. So a cd is visible without anything being injected
; into the shell.
;
; It fails to nothing rather than to something wrong. A title that is not a
; path - which is what Claude CLI and anything else that names its task
; produces - is skipped, and the last report stands.
;
; This is a forwarder only because no shell reports for itself yet. A shell
; plugin is the honest fix, since the shell is the only thing that actually
; knows where it is, and it would forward the terminal's identity rather than
; its own pid. See todo.md.

#Include gluc-http.ahk

global GLUC_TERMINAL_LAST := Map()

GlucTerminalStart()

GlucTerminalStart()
{
    SetTimer(GlucTerminalScan, 400)
    A_IconTip := "gluc terminal - nothing reported yet"
}

GlucTerminalScan()
{
    global GLUC_TERMINAL_LAST

    live := Map()
    for hwnd in WinGetList("ahk_class CASCADIA_HOSTING_WINDOW_CLASS")
    {
        path := GlucTerminalPath(hwnd)
        if (path = "")
            continue

        live[hwnd] := path

        ; Only when it changes. A terminal sitting in one directory is not news.
        if (GLUC_TERMINAL_LAST.Has(hwnd) && GLUC_TERMINAL_LAST[hwnd] = path)
            continue

        reply := GlucSend("event", GlucEventJson("select", "terminal", GlucWindowJson(hwnd), path))
        if (GlucLastError = "")
            A_IconTip := "gluc terminal`n" path
        else
            A_IconTip := "gluc terminal`nhost not reachable`n" GlucLastError
    }

    GLUC_TERMINAL_LAST := live
}

GlucTerminalPath(hwnd)
{
    try
        title := WinGetTitle("ahk_id " hwnd)
    catch
        return ""

    title := RegExReplace(title, "\s*[-\x{2014}]\s*Windows Terminal\s*$", "")
    title := Trim(title)
    return GlucIsFilesystemPath(title) ? title : ""
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
