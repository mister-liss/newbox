; Windows Terminal, by window title. PowerShell 7 sets the tab title to the
; current directory via OSC 9;9, and WT mirrors the active tab into the window
; title, so this sees a cd without anything being injected into the shell.
;
; It fails to nothing rather than to something wrong. A title that is not a
; path - which is what Claude CLI and anything else that names its task
; produces - returns "", and the context stays where it was.
;
; That failure is common enough to be worth replacing eventually. See todo.md:
; reading the shell's own report is the honest fix, since the shell is the only
; thing that knows where it is.

class GlucTerminalExtractor
{
    static source       := "wt"
    static pollInterval := 400

    static Match(hwnd, pname, cls)
    {
        return (cls = "CASCADIA_HOSTING_WINDOW_CLASS")
    }

    static Identify(hwnd)
    {
        return this.FromTitle(hwnd)
    }

    static Poll(hwnd)
    {
        return this.FromTitle(hwnd)
    }

    static FromTitle(hwnd)
    {
        try
            title := WinGetTitle("ahk_id " hwnd)
        catch
            return ""
        title := RegExReplace(title, "\s*[-\x{2014}]\s*Windows Terminal\s*$", "")
        title := Trim(title)
        if (!GlucIsFilesystemPath(title))
            return ""
        path := GlucNormalizePath(title)
        return { id: hwnd, path: path }
    }
}

GlucRegisterExtractor(GlucTerminalExtractor)
