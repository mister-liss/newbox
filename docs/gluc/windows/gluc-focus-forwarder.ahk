#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; The windows focus forwarder.
;
; Reports every foreground change and nothing else. It has no knowledge of any
; application: it does not know what an Explorer window is, cannot read a
; terminal title, and never decides that a window is uninteresting. Deciding
; which windows counted is what used to give one app a standing the others did
; not have, and it is why a browser or a gvim window reported nothing at all.
;
; Focus is the one thing only the OS knows. An app can report what it is
; looking at, but it cannot know whether you are looking at it - so no plugin
; or forwarder ever sends a focus event, and this is the only sender.
;
; It reports both parts of the identity because it is the only reporter that
; can see both, and the other side of a join may have either: vim knows only
; its process, the Explorer forwarder only its window.
;
; Unelevated on purpose, same as the other forwarders.

#Include gluc-http.ahk

global GLUC_HOOK     := 0
global GLUC_CALLBACK := 0
global GLUC_LAST     := ""

GlucFocusStart()

GlucFocusStart()
{
    global GLUC_HOOK, GLUC_CALLBACK
    EVENT_SYSTEM_FOREGROUND := 0x0003
    WINEVENT_OUTOFCONTEXT   := 0x0000

    GLUC_CALLBACK := CallbackCreate(GlucOnForeground, "F", 7)
    GLUC_HOOK := DllCall("SetWinEventHook"
        , "UInt", EVENT_SYSTEM_FOREGROUND, "UInt", EVENT_SYSTEM_FOREGROUND
        , "Ptr", 0, "Ptr", GLUC_CALLBACK, "UInt", 0, "UInt", 0
        , "UInt", WINEVENT_OUTOFCONTEXT, "Ptr")

    OnExit(GlucFocusStop)
    A_IconTip := "gluc focus - nothing reported yet"

    ; Whatever is already in front when this starts is as much a focus change
    ; as the next one, and without it nothing is reported until you alt-tab.
    SetTimer(() => GlucOnForeground(0, 0, WinExist("A"), 0, 0, 0, 0), -100)
}

GlucFocusStop(reason := "", code := 0)
{
    global GLUC_HOOK, GLUC_CALLBACK
    if (GLUC_HOOK)
    {
        DllCall("UnhookWinEvent", "Ptr", GLUC_HOOK)
        GLUC_HOOK := 0
    }
    if (GLUC_CALLBACK)
    {
        CallbackFree(GLUC_CALLBACK)
        GLUC_CALLBACK := 0
    }
}

GlucOnForeground(hook, ev, hwnd, idObject, idChild, idThread, time)
{
    global GLUC_LAST

    ; Only real top-level windows. The hook also fires for menus, tooltips and
    ; the taskbar, and those are not somewhere you are working.
    if (!hwnd || idObject != 0)
        return
    try
        if (!WinExist("ahk_id " hwnd))
            return
    catch
        return

    try
        pid := WinGetPID("ahk_id " hwnd)
    catch
        return

    ; The same window coming forward twice is not news.
    if (hwnd = GLUC_LAST)
        return
    GLUC_LAST := hwnd

    name := ""
    try
        name := WinGetProcessName("ahk_id " hwnd)
    catch
        name := ""

    reply := GlucSend("event", GlucEventJson("focus", "windows", GlucWindowProcessJson(hwnd, pid)))
    if (GlucLastError = "")
        A_IconTip := "gluc focus`n" name " (" pid ")"
    else
        A_IconTip := "gluc focus`nhost not reachable`n" GlucLastError
}
