; Explorer. Supplies the path itself over Shell COM, so nothing else has to
; report on its behalf - Explorer has no way to report for itself and this is
; the exception that makes the optional path in the contract worth having.

class GlucExplorerExtractor
{
    static source       := "explorer"
    static pollInterval := 300

    static Match(hwnd, pname, cls)
    {
        return (cls = "CabinetWClass" || cls = "ExploreWClass")
    }

    static Identify(hwnd)
    {
        path := this.ExtractPath(hwnd)
        if (path = "")
            return ""
        return { id: hwnd, path: path }
    }

    static Poll(hwnd)
    {
        return this.Identify(hwnd)
    }

    static ExtractPath(hwnd)
    {
        seen := 0
        try
            wins := ComObject("Shell.Application").Windows
        catch as e
        {
            GlucLog("  explorer: COM failed - " e.Message)
            return ""
        }
        for w in wins
        {
            seen += 1
            try
                other := w.HWND
            catch as e
            {
                GlucLog("  explorer: window " seen " unreadable - " e.Message)
                continue
            }
            if (other != hwnd)
            {
                GlucLog("  explorer: window " seen " hwnd=" other " (not ours)")
                continue
            }
            try
                raw := w.Document.Folder.Self.Path
            catch as e
            {
                GlucLog("  explorer: ours but no folder - " e.Message)
                continue
            }
            GlucLog("  explorer: ours, raw=" raw)
            if (GlucIsFilesystemPath(raw))
                return GlucNormalizePath(raw)
            GlucLog("  explorer: rejected, not a filesystem path")
            return ""
        }
        GlucLog("  explorer: COM listed " seen " window(s), none matched " hwnd)
        return ""
    }
}

GlucRegisterExtractor(GlucExplorerExtractor)
