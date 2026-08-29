; Focus watcher kernel. Ported from eedee, which worked this out first.
;
; No per-app logic lives here. Extractors register themselves and this
; dispatches the foreground window to whichever one claims it.
;
; Extractor contract:
;
;   static source        tag sent with the report
;   static pollInterval  ms, 0 to disable in-app polling
;   static Match(hwnd, pname, cls)       is this window mine?
;   static Identify(hwnd) -> {id, path?} on focus change
;   static Poll(hwnd)     -> {id, path?} while it stays focused
;
; Return "" for "nothing this tick" and the context stays where it was.
; An unrecognised window reports nothing at all, which is what makes focus
; sticky across everything nobody has written an extractor for.
;
; An id only has to mean something within its source. A shell's is its pid,
; so a shell reporting its own path can be joined to this. Explorer's is a
; window handle, because the extractor supplies the path itself and there is
; nothing to join.

global GLUC_EXTRACTORS   := []
global GLUC_LAST_KEY     := ""
global GLUC_HOOK         := 0
global GLUC_CALLBACK     := 0
global GLUC_POLL_HWND    := 0
global GLUC_POLL_EXTRACTOR := ""

GlucRegisterExtractor(extractor)
{
    global GLUC_EXTRACTORS
    GLUC_EXTRACTORS.Push(extractor)
}

GlucWatchStart()
{
    global GLUC_HOOK, GLUC_CALLBACK
    EVENT_SYSTEM_FOREGROUND := 0x0003
    WINEVENT_OUTOFCONTEXT   := 0x0000
    GLUC_CALLBACK := CallbackCreate(GlucOnForeground, "F", 7)
    GLUC_HOOK := DllCall("SetWinEventHook"
        , "UInt", EVENT_SYSTEM_FOREGROUND, "UInt", EVENT_SYSTEM_FOREGROUND
        , "Ptr", 0, "Ptr", GLUC_CALLBACK, "UInt", 0, "UInt", 0
        , "UInt", WINEVENT_OUTOFCONTEXT, "Ptr")
    OnExit(GlucWatchStop)
    GlucTrayInit()
    SetTimer(() => GlucOnForeground(0, 0, WinExist("A"), 0, 0, 0, 0), -100)
}

GlucWatchStop(reason := "", code := 0)
{
    global GLUC_HOOK, GLUC_CALLBACK, GLUC_POLL_HWND, GLUC_POLL_EXTRACTOR
    SetTimer(GlucPollActive, 0)
    GLUC_POLL_HWND := 0
    GLUC_POLL_EXTRACTOR := ""
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
    global GLUC_EXTRACTORS, GLUC_POLL_HWND, GLUC_POLL_EXTRACTOR
    if (!hwnd)
        return
    try
    {
        cls   := WinGetClass("ahk_id " hwnd)
        wpid  := WinGetPID("ahk_id " hwnd)
        pname := ProcessGetName(wpid)
    }
    catch as e
    {
        GlucLog("foreground: could not read window " hwnd " - " e.Message)
        return
    }
    GlucLog("foreground hwnd=" hwnd " cls=" cls " pname=" pname)

    matched := ""
    for ext in GLUC_EXTRACTORS
    {
        try
        {
            if (ext.Match(hwnd, pname, cls))
            {
                matched := ext
                break
            }
        }
        catch
            continue
    }

    if (GLUC_POLL_HWND != hwnd || GLUC_POLL_EXTRACTOR != matched)
    {
        SetTimer(GlucPollActive, 0)
        GLUC_POLL_HWND := 0
        GLUC_POLL_EXTRACTOR := ""
    }

    if (!matched)
    {
        GlucLog("  no extractor claimed it - staying sticky")
        return
    }
    GlucLog("  matched " matched.source)

    result := ""
    try
        result := matched.Identify(hwnd)
    catch
        return
    GlucDispatch(matched, result)

    if (matched.HasOwnProp("pollInterval") && matched.pollInterval > 0)
    {
        GLUC_POLL_HWND := hwnd
        GLUC_POLL_EXTRACTOR := matched
        SetTimer(GlucPollActive, matched.pollInterval)
    }
}

; Re-asks the matched extractor while its window stays foreground, so
; navigating inside an app is seen without a focus change.
GlucPollActive()
{
    global GLUC_POLL_HWND, GLUC_POLL_EXTRACTOR
    extractor := GLUC_POLL_EXTRACTOR
    hwnd      := GLUC_POLL_HWND
    if (!hwnd || !IsObject(extractor) || !WinExist("ahk_id " hwnd))
    {
        SetTimer(GlucPollActive, 0)
        GLUC_POLL_HWND := 0
        GLUC_POLL_EXTRACTOR := ""
        return
    }
    result := ""
    try
        result := extractor.Poll(hwnd)
    catch
        return
    GlucDispatch(extractor, result)
}

; Report then focus, deduped. Report first so the session exists by the time
; focus names it - focus on an unknown session is ignored on purpose.
GlucDispatch(extractor, result)
{
    global GLUC_LAST_KEY, GlucLastError
    if (!IsObject(result) || !result.HasOwnProp("id"))
        return
    id   := result.id
    path := result.HasOwnProp("path") ? result.path : ""
    key  := extractor.source ":" id "|" path
    if (key = GLUC_LAST_KEY)
        return
    GLUC_LAST_KEY := key
    GlucLog("  dispatch " extractor.source ":" id " path=" (path = "" ? "(none)" : path))

    if (path != "")
    {
        r1 := GlucSend("report`t" GlucReportJson(extractor.source, id, path))
        GlucLog("  report reply=[" r1 "] err=" GlucLastError)
    }
    reply := GlucSend("focus`t" extractor.source "`t" id)
    GlucLog("  focus reply=[" reply "] err=" GlucLastError)

    ; The tray tip is the only place this is visible. Reporting is silent when
    ; the host is down, which is exactly when you want to be told.
    if (reply = "")
    {
        global GlucLastError
        GlucLog("  send failed, CreateFile error " GlucLastError)
        GlucTip("host not reachable (err " GlucLastError ")`n" extractor.source ":" id)
    }
    else
        GlucTip(extractor.source ":" id (path != "" ? "`n" path : "`nno path"))
}

GlucLog(text)
{
    try
        FileAppend(FormatTime(, "HH:mm:ss") " " text "`n", EnvGet("LOCALAPPDATA") "\gluc\watcher.log")
    catch
        return
}

GlucTip(text)
{
    A_IconTip := "gluc`n" text
}

GlucTrayInit()
{
    A_IconTip := "gluc - nothing reported yet"
    A_TrayMenu.Insert("1&", "&Re-report focused window", GlucRepush)
    A_TrayMenu.Insert("2&", "Show &context", GlucShowContext)
    A_TrayMenu.Insert("3&")
    A_TrayMenu.Default := "&Re-report focused window"
}

; Clears the dedup so the same window reports again - the only way to retry
; after the host was restarted underneath us.
GlucRepush(*)
{
    global GLUC_LAST_KEY
    GLUC_LAST_KEY := ""
    GlucOnForeground(0, 0, WinExist("A"), 0, 0, 0, 0)
}

GlucShowContext(*)
{
    reply := GlucSend("context")
    MsgBox(reply = "" ? "host not reachable" : reply, "gluc context", "Iconi")
}

GlucReportJson(source, id, path)
{
    return '{"source":"' GlucJsonEscape(source) '","id":"' GlucJsonEscape(id) '","path":"' GlucJsonEscape(path) '"}'
}

GlucJsonEscape(s)
{
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    return s
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
