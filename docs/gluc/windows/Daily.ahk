#Requires AutoHotkey v2.0

#Include gluc-pipe.ahk

WtPath() => EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\wt.exe"

XButton1::
{
    Send("#-")
}

XButton2::#=

; ---- Win+T in Explorer: a terminal on that folder --------------------
#HotIf WinActive("ahk_class CabinetWClass")
#t::
{
    dir := ExplorerPath()
    if (dir != "")
        Run WtPath() ' -d "' dir '"'
    else
        Run WtPath()   ; This PC, Control Panel, search results
}

; ---- Ctrl+V in Explorer: write a clipboard image out as a file -------
^v::
{
    static CF_DIB := 8, CF_HDROP := 15
    if (DllCall("IsClipboardFormatAvailable", "UInt", CF_HDROP)
        || !DllCall("IsClipboardFormatAvailable", "UInt", CF_DIB))
    {
        Send "^v"
        return
    }
    dir := ExplorerPath()
    if (dir = "")
    {
        Send "^v"
        return
    }
    saver := EnvGet("LOCALAPPDATA") "\gluc\paste-image.ps1"
    if (!FileExist(saver))
    {
        Send "^v"
        return
    }
    RunWait 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' saver '" -Directory "' dir '"', , "Hide"
}
#HotIf

ExplorerPath()
{
    hwnd := WinGetID("A")
    for window in ComObject("Shell.Application").Windows
    {
        if (window.HWND != hwnd)
            continue
        return StrReplace(window.Document.Folder.Self.Path, "\", "/")
    }
    return ""
}

; ---- Win+T in Windows Terminal: another terminal, same cwd -----------
#HotIf WinActive("ahk_exe WindowsTerminal.exe")
#t::
{
    dir := TermCwd(WinGetPID("A"), WinGetTitle("A"))
    if (dir != "")
        Run WtPath() ' -d "' dir '"'
    else
        Run WtPath()
}
#HotIf

; ---- Win+T anywhere else ---------------------------------------------
#t::Run WtPath()

#g::GlucSend("recent")

#c::PlaceWin()

PlaceWin()
{
    static BAND := 0.30
    MonitorGetWorkArea(, &l, &t, &r, &b)
    w := Round((r - l) * BAND)
    h := (b - t) // 3
    WinMove l + (r - l - w) // 2, t + (b - t - h) // 2, w, h, "A"
}


; Windows Terminal hosts OpenConsole.exe children, and the shell sits
; under those. Walk the tree for a process whose cwd we can read.
TermCwd(wtPid, title)
{
    best := "", bestDepth := -1
    for cand in ProcDescendants(wtPid)
    {
        cwd := PebReadCwd(cand.pid)
        if (cwd == "")
            continue
        cwd := RTrim(cwd, "\/")
        if (SubStr(cwd, -1) == ":")      ; a drive root - keep it valid
            cwd .= "\"
        ; Several tabs means several shells. The window title tracks the
        ; ACTIVE tab, so prefer a shell whose folder the title names.
        SplitPath cwd, &leaf
        if (leaf != "" && InStr(title, leaf))
            return cwd
        ; Otherwise the innermost process - for an agent session that is
        ; the agent itself, whose cwd is the one that matters.
        if (cand.depth > bestDepth)
        {
            bestDepth := cand.depth
            best := cwd
        }
    }
    return best
}

; One Toolhelp snapshot, walked in memory. This was WMI first, which cost
; a query per process and took seconds on a deep tree.
ProcDescendants(rootPid)
{
    static TH32CS_SNAPPROCESS := 0x02
    static SIZEOF_PE32W       := 568   ; x64, padded from 564

    kids := Map()
    snap := DllCall("CreateToolhelp32Snapshot", "UInt", TH32CS_SNAPPROCESS, "UInt", 0, "Ptr")
    if (snap == -1)
        return []
    try
    {
        pe := Buffer(SIZEOF_PE32W, 0)
        NumPut("UInt", SIZEOF_PE32W, pe, 0)
        if (!DllCall("Process32FirstW", "Ptr", snap, "Ptr", pe))
            return []
        loop
        {
            pid  := NumGet(pe, 8,  "UInt")   ; th32ProcessID
            ppid := NumGet(pe, 32, "UInt")   ; th32ParentProcessID
            if (!kids.Has(ppid))
                kids[ppid] := []
            kids[ppid].Push(pid)
            if (!DllCall("Process32NextW", "Ptr", snap, "Ptr", pe))
                break
        }
    }
    finally
    {
        DllCall("CloseHandle", "Ptr", snap)
    }

    out := [], queue := [{ pid: rootPid, depth: 0 }]
    while (queue.Length)
    {
        cur := queue.RemoveAt(1)
        if (cur.depth > 0)
            out.Push(cur)
        if (cur.depth >= 6 || !kids.Has(cur.pid))
            continue
        for k in kids[cur.pid]
            queue.Push({ pid: k, depth: cur.depth + 1 })
    }
    return out
}


; --- Read a process's cwd out of its PEB. -----------------------------
; Lifted from S:\prj\eedee\ahk\lib\peb.ahk and inlined deliberately, so
; this script does not fail to load if that repo moves.
; x64 offsets: PBI.PebBaseAddress +0x08, PEB.ProcessParameters +0x20,
; RTL_USER_PROCESS_PARAMETERS.CurrentDirectory.DosPath +0x38.

PebReadCwd(pid)
{
    static PROCESS_QUERY_INFORMATION := 0x0400
    static PROCESS_VM_READ           := 0x0010

    hProc := DllCall("OpenProcess"
        , "UInt", PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
        , "Int" , 0
        , "UInt", pid
        , "Ptr")
    if (!hProc)
        return ""

    try
    {
        pbi := Buffer(48, 0)
        status := DllCall("ntdll\NtQueryInformationProcess"
            , "Ptr"  , hProc
            , "UInt" , 0           ; ProcessBasicInformation
            , "Ptr"  , pbi
            , "UInt" , 48
            , "UInt*", &returned := 0)
        if (status != 0)
            return ""
        pebAddr := NumGet(pbi, 8, "Ptr")
        if (!pebAddr)
            return ""
        ppPtr := PebReadPtr(hProc, pebAddr + 0x20)
        if (!ppPtr)
            return ""
        us := Buffer(16, 0)
        if (!PebReadMem(hProc, ppPtr + 0x38, us, 16))
            return ""
        length := NumGet(us, 0, "UShort")
        bufPtr := NumGet(us, 8, "Ptr")
        if (length == 0 || !bufPtr)
            return ""
        pathBuf := Buffer(length + 2, 0)
        if (!PebReadMem(hProc, bufPtr, pathBuf, length))
            return ""
        NumPut("UShort", 0, pathBuf, length)
        return StrGet(pathBuf, "UTF-16")
    }
    finally
    {
        DllCall("CloseHandle", "Ptr", hProc)
    }
}

PebReadMem(hProc, addr, buf, size)
{
    return DllCall("ReadProcessMemory"
        , "Ptr" , hProc
        , "Ptr" , addr
        , "Ptr" , buf
        , "Ptr" , size
        , "Ptr*", &read := 0)
}

PebReadPtr(hProc, addr)
{
    p := Buffer(8, 0)
    if (!PebReadMem(hProc, addr, p, 8))
        return 0
    return NumGet(p, 0, "Ptr")
}
