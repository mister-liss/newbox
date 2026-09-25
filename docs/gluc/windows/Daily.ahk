#Requires AutoHotkey v2.0
; Like the three forwarders, and for the same reason with a sharper edge: this
; one registers hotkeys. Two instances means two handlers for Win+T, and the
; build kills the host with Stop-Process rather than asking it to stop, so the
; supervisor never gets to clean up and every rebuild left another copy behind.
; Seven were running before this line existed.
#SingleInstance Force

#Include gluc-http.ahk

; Ask the host to start something. This script never launches a program.
;
; It is elevated - it has to be, to send input while an elevated window has
; focus - and a process launches its children with its own token, so anything
; it starts is an administrator process. Win+T was handing out administrator
; terminals, and everything started from one inherited it.
;
; The host is elevated too but knows how to hand a token back, so it does the
; launching. What a terminal IS lives in devnext's programs.json; neither this
; script nor gluc names a program.
GlucLaunch(intent, dir)
{
    ; Hand the foreground over before asking, because the host cannot.
    ;
    ; Windows grants the right to call SetForegroundWindow to a process that is
    ; foreground, was started by the one that is, or just handled input. On a
    ; hotkey that process is this script - which is why the hotkey ran at all -
    ; and it is not the host. The host starts the terminal, so its own
    ; AllowSetForegroundWindow call has nothing to give away and the new window
    ; opens behind whatever you were looking at.
    ;
    ; ASFW_ANY releases the lock for whoever asks next, which is the window the
    ; host is about to create. The same belt and braces as Win+P below, for the
    ; same reason and one indirection further away.
    DllCall("AllowSetForegroundWindow", "UInt", 0xFFFFFFFF)

    body := '{"intent":"' intent '","path":"' GlucJsonEscape(dir) '"}'
    reply := GlucSend("launch", body)
    if (GlucLastError != "")
        TrayTip("gluc", "could not reach the host: " GlucLastError)
    else if (SubStr(reply, 1, 1) = "!")
        TrayTip("gluc", SubStr(reply, 2))
}

XButton1::
{
    Send("#-")
}

XButton2::#=

; ---- Win+T in Explorer -----------------------------------------------
; GONE, and that is the fix rather than a regression.
;
; This branch read the focused Explorer window over COM and passed the
; folder to the host. Two things wrong with that. It is the hotkey script
; doing work instead of naming an intent, which is the one thing this file
; is not for. And this script is elevated, while reading another process's
; Explorer window over COM is refused across an integrity boundary - which
; is the documented reason gluc-explorer-forwarder.ahk runs unelevated.
;
; The forwarder already reports exactly this, keyed by window handle, so
; focus-project resolves an Explorer window like any other. Win+T below
; needs no special case: it asks gluc, and gluc was already told.

; ---- Ctrl+V in Explorer: write a clipboard image out as a file -------
;
; Still guarded to Explorer. Deleting the Win+T branch above took this
; directive with it for a moment, which would have made Ctrl+V a global
; hotkey - every paste in every application routed through here.
#HotIf WinActive("ahk_class CabinetWClass")
^v::
{
    static CF_DIB := 8, CF_HDROP := 15
    if (DllCall("IsClipboardFormatAvailable", "UInt", CF_HDROP)
        || !DllCall("IsClipboardFormatAvailable", "UInt", CF_DIB))
    {
        Send "^v"
        return
    }
    ; An intent, not a command. The host knows where focus is and owns the
    ; saver; this only knows that the clipboard holds an image and that a
    ; keystroke is waiting on the answer.
    ;
    ; Falls through to a real Ctrl+V when the host cannot place the window,
    ; which is the same behaviour as before and matters: swallowing the key
    ; would make a paste silently do nothing.
    reply := GlucSend("paste", "{}")
    if (GlucLastError != "" || SubStr(reply, 1, 1) = "!")
        Send "^v"
}
#HotIf


; ---- Win+T in Windows Terminal: another terminal, same cwd -----------
; The focused shell says where it is, so this asks gluc rather than working it
; out. It used to walk every process under the terminal window, read each one's
; PEB for a current directory and take the deepest path - with five shells
; under one Windows Terminal process that is an arbitrary tiebreak, not the one
; you are typing in.
;
; The shell that reports is the shell that has focus, which is the question
; being asked. A shell with no gluc plugin reports nothing and this falls back
; to a plain terminal; the old code would have guessed instead, and a wrong
; folder is worse than none.
#HotIf WinActive("ahk_exe WindowsTerminal.exe")
#t::
{
    dir := GlucFocusTarget()
    if (dir != "")
        GlucLaunch("terminal", dir)
    else
        GlucLaunch("terminal", "")
}
#HotIf

; ---- Win+T anywhere else ---------------------------------------------
; Anywhere else means gvim, an agent window, a browser - and gluc knows where
; those are looking just as well as it knows a terminal. This used to open at
; the home directory: it passed no path, so the host fell back to the profile,
; while the answer sat in the store unasked for.
;
; Explorer keeps its own branch above because it can be read directly and
; instantly; everything else goes through what was reported.
#t::GlucLaunch("terminal", GlucFocusTarget())

#g::GlucSend("recent")

; ---- Win+E: Explorer on the project you are in ----------------------
; Home is a fine answer when gluc does not know where you are and a poor one
; when it does. Falls back to plain Explorer rather than refusing, so the key
; keeps working with the host down.
#e::
{
    dir := GlucProject()
    if (dir != "")
        Run 'explorer.exe "' dir '"'
    else
        Run "explorer.exe"
}

; The project you are in, as gluc sees it. Consumer policy, so it lives here
; rather than in the client: the newest focus-project that names one, not
; simply the newest. A null means focus moved somewhere gluc knows nothing
; about, and the useful answer then is the last place it did know.
GlucProject()
{
    return GlucJsonUnescape(GlucFocusField("project"))
}

; Where focus is, rather than which project holds it: the folder a shell is in
; or an Explorer window is showing. It is a file when a file has focus, so a
; caller that wants a folder takes the parent.
; Where to open something, for the window you are looking at.
;
; The newest row that says anything, at whatever resolution that reporter
; knows. A shell reports a path, so you get the folder you are actually in. A
; reporter that only knows a project - an agent plugin, say - reports that, and
; the project is the right answer for it rather than a degraded one. A row that
; says neither means focus moved somewhere gluc knows nothing about, and the
; useful answer then is the last place it did know.
;
; Read row by row rather than by scanning the whole reply for a field, which is
; what this used to do: that finds the newest row CARRYING the field, so a
; window reporting only a project would be skipped over in favour of some older
; window's path. The answer has to come from one row - the one in front of you.
GlucFocusTarget()
{
    reply := GlucSend("query", '{"kinds":["focus-project"],"limit":20}')
    if (GlucLastError != "" || reply = "")
        return ""

    pos := 1
    while (RegExMatch(reply, '\{[^{}]*\}', &row, pos))
    {
        pos := row.Pos + row.Len
        if (RegExMatch(row[0], '"path":"([^"]*)"', &m) && m[1] != "")
            return GlucFolderOf(GlucJsonUnescape(m[1]))
        if (RegExMatch(row[0], '"project":"([^"]*)"', &m) && m[1] != "")
            return GlucJsonUnescape(m[1])
    }
    return ""
}

; A file's folder, a folder as itself. Reporters send whichever they have and
; should not have to agree on which.
GlucFolderOf(path)
{
    if (DirExist(path))
        return path
    SplitPath path, , &parent
    return parent
}

GlucFocusField(name)
{
    reply := GlucSend("query", '{"kinds":["focus-project"],"limit":20}')
    if (GlucLastError != "" || reply = "")
        return ""
    ; Newest first, so the first element carrying the field is the one wanted -
    ; and a null is not a quoted string, which is what lets one pattern stand in
    ; for a parse. "projectName" does not match "project": the key is compared
    ; whole, up to its closing quote.
    if (!RegExMatch(reply, '"' name '":"([^"]*)"', &m))
        return ""
    return StrReplace(m[1], "\\", "\")
}

; ---- Win+P: read a colour off the screen ----------------------------
; Steals the projector menu, which this machine has never needed. The
; picker captures the screen at startup and exits on its own, so it is
; not supervised - it just runs.
;
; Launched directly, and that matters. Windows only lets a process take the
; foreground if it has standing: it is the foreground process, it was started
; by the foreground process, or it just handled input. This script just handled
; input - that is why the hotkey ran - so a child of it inherits standing and
; the picker can raise itself.
;
; Going through explorer.exe to de-elevate broke exactly that. The picker
; became Explorer's child rather than this script's, so it inherited standing
; only when Explorer happened to be the foreground process - which is to say
; when the desktop had focus, and never when a real window did.
;
; So it runs elevated, which it does not need and should not have. That is a
; separate problem from being able to answer the keyboard, and worth solving
; without giving up the foreground again.
#p::
{
    ; Hand standing over, then ask. Exactly what Win+T does, and for the same
    ; reason: the host starts it, so it is not a child of this elevated script
    ; and does not inherit administrator from it.
    ;
    ; This was launched directly for years on the recorded grounds that a
    ; granted foreground expires before a cold .NET process can use it. Two
    ; things say otherwise. Win+T grants and then survives an HTTP round trip
    ; AND a process launch. And the picker is 500ms cold, 10-25ms warm, which
    ; is the same order - measured, not assumed.
    DllCall("AllowSetForegroundWindow", "UInt", 0xFFFFFFFF)

    ; Falls back to launching it here when the host is not answering, because
    ; a colour picker that needs a daemon to exist is worse than one that is
    ; briefly elevated. Same shape as Win+E falling back to plain Explorer.
    reply := GlucSend("picker", "{}")
    if (GlucLastError != "" || SubStr(reply, 1, 1) = "!")
        Run EnvGet("LOCALAPPDATA") "\gluc\Gluc.Picker.exe"
}

#c::PlaceWin()

PlaceWin()
{
    static BAND := 0.30
    MonitorGetWorkArea(, &l, &t, &r, &b)
    w := Round((r - l) * BAND)
    h := (b - t) // 3
    WinMove l + (r - l - w) // 2, t + (b - t - h) // 2, w, h, "A"
}
