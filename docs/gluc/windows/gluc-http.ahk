global GlucLastError := ""
global GlucPort := ""
global GlucToken := ""
global GlucHostPid := 0

; Talking to the host. Both halves need this: the hotkeys ask it things, the
; watcher tells it things.
;
; The host holds the logic and the state; this only carries a message to it and
; brings the reply back. Silent when the host is down - a dead host must never
; make a hotkey hang, which is what the timeouts are for.
;
; GlucLastError is empty on success and describes the failure otherwise. Check
; that rather than the reply, which is only meaningful when the call succeeded.
GlucSend(verb, body := "{}")
{
    global GlucLastError, GlucPort, GlucHostPid

    if (GlucPort = "" && !GlucReadEndpoint())
    {
        GlucLastError := "no endpoint file - host not running?"
        return ""
    }

    ; Cheap and decisive. Without it a dead host costs two seconds per call,
    ; because WinHttp will not give up on a closed loopback port any sooner
    ; however short its connect timeout is set.
    if (!ProcessExist(GlucHostPid))
    {
        GlucPort := ""
        if (!GlucReadEndpoint() || !ProcessExist(GlucHostPid))
        {
            GlucLastError := "host not running"
            return ""
        }
    }

    reply := GlucTry(verb, body)
    if (GlucLastError = "")
        return reply

    ; The port is ephemeral, so a failure is often just the host having
    ; restarted on a new one. Worth one more go - but only if the file now says
    ; something different, because retrying a port that is genuinely dead only
    ; doubles the wait, and this is on the way to a hotkey.
    stale := GlucPort
    GlucPort := ""
    if (!GlucReadEndpoint() || GlucPort = stale)
        return ""
    return GlucTry(verb, body)
}

; Where the host is, and what gets us in. A loopback port is reachable by
; anything on the machine, so the token stands in for the access control the
; pipe used to get from its DACL: the file is in the user's profile, so nobody
; else can read it and nobody else can connect.
GlucReadEndpoint()
{
    global GlucPort, GlucToken, GlucHostPid
    try
        text := FileRead(EnvGet("LOCALAPPDATA") "\gluc\endpoint", "UTF-8")
    catch
        return false
    lines := StrSplit(Trim(text, " `t`r`n"), "`n")
    if (lines.Length < 3)
        return false
    GlucPort := Trim(lines[1], " `t`r`n")
    GlucToken := Trim(lines[2], " `t`r`n")
    GlucHostPid := Integer(Trim(lines[3], " `t`r`n"))
    return GlucPort != "" && GlucToken != ""
}

GlucTry(verb, body)
{
    global GlucLastError, GlucPort, GlucToken
    static request := ""

    GlucLastError := ""
    try
    {
        ; Held across calls so the connection stays up. The watcher sends on
        ; every foreground change, and that is not the place to pay for a new
        ; socket each time.
        if (request = "")
            request := ComObject("WinHttp.WinHttpRequest.5.1")

        ; Short on the way out, generous on the way back: nothing here needs
        ; longer than a moment to connect, but showing the switcher blocks the
        ; reply until the window is up.
        request.SetTimeouts(300, 300, 1000, 10000)
        request.Open("POST", "http://127.0.0.1:" GlucPort "/" verb, false)
        request.SetRequestHeader("Authorization", "Bearer " GlucToken)
        request.SetRequestHeader("Content-Type", "application/json")
        request.Send(body)
        status := request.Status
        reply  := Trim(request.ResponseText, " `t`r`n")
    }
    catch as e
    {
        request := ""
        GlucLastError := "unreachable: " GlucOneLine(e.Message)
        return ""
    }

    if (status != 200)
    {
        GlucLastError := "http " status ": " GlucOneLine(reply)
        return ""
    }
    return reply
}

; COM hands back multi-line messages with a trailing source line. This has to
; fit in a tray tip.
GlucOneLine(text)
{
    text := RegExReplace(text, "\s*(`r`n|`n|`r)\s*", " ")
    return SubStr(Trim(text), 1, 120)
}

; Kinds are written as literals at the call site rather than held in constants
; here. A top-level assignment in an included file only runs when the include
; is reached in the auto-execute flow, so a constant is quietly unassigned for
; anything that includes late - a failure that looks nothing like its cause.
;
; The vocabulary is closed and the host rejects anything outside it, so a typo
; is a 400 rather than a silent miss. Gluc.Core/EventKind.cs is where it lives:
; focus, select, open, close, write.

; Building the messages, kept next to the thing that sends them so anything
; that includes this can talk without dragging in the watcher as well.
;
; No timestamp: the host stamps arrival. Loopback latency is nothing, and it
; keeps every producer out of the business of getting an offset right.
GlucEventJson(kind, source, id, path := "")
{
    json := '{"kind":"' GlucJsonEscape(kind) '"'
        . ',"source":"' GlucJsonEscape(source) '"'
        . ',"id":"' GlucJsonEscape(id) '"'
    if (path != "")
        json .= ',"path":"' GlucJsonEscape(path) '"'
    return json "}"
}

GlucJsonEscape(s)
{
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    return s
}
