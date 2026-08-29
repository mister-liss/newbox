global GlucLastError := 0

; Talking to the host. Both halves need this: the hotkeys ask it things, the
; watcher tells it things. Silent when it is not running - a dead host must not
; make a hotkey hang.

; The host holds the logic and the state; this only carries a line to it and
; brings one back. Silent when it is not running, so a dead host costs nothing.
GlucSend(command)
{
    global GlucLastError
    static GENERIC_READ := 0x80000000, GENERIC_WRITE := 0x40000000, OPEN_EXISTING := 3

    h := DllCall("CreateFileW", "Str", "\\.\pipe\gluc"
        , "UInt", GENERIC_READ | GENERIC_WRITE, "UInt", 0, "Ptr", 0
        , "UInt", OPEN_EXISTING, "UInt", 0, "Ptr", 0, "Ptr")
    if (h = -1 || h = 0)
    {
        GlucLastError := DllCall("GetLastError", "UInt")
        return ""
    }
    GlucLastError := 0

    try
    {
        line := command . "`n"
        size := StrPut(line, "UTF-8") - 1
        buf := Buffer(size)
        StrPut(line, buf, "UTF-8")
        if (!DllCall("WriteFile", "Ptr", h, "Ptr", buf, "UInt", size, "UInt*", &written := 0, "Ptr", 0))
        {
            GlucLastError := DllCall("GetLastError", "UInt")
            return ""
        }

        out := Buffer(4096, 0)
        if (!DllCall("ReadFile", "Ptr", h, "Ptr", out, "UInt", 4095, "UInt*", &read := 0, "Ptr", 0))
        {
            GlucLastError := DllCall("GetLastError", "UInt")
            return ""
        }
        return Trim(StrGet(out, read, "UTF-8"), " `t`r`n")
    }
    finally
    {
        DllCall("CloseHandle", "Ptr", h)
    }
}
