; Legacy compatibility entry point. New launches should use super-hotkey.ahk.
#Include "%A_ScriptDir%\super-hotkey.ahk"

if A_LineFile = A_ScriptFullPath
    SHW_Main()
