; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; logging
; =============================================================================

InitializeDebugLogging(reason := "started")
{
    global debug_enabled, debug_data_directory

    if !debug_enabled
        return

    try DirCreate(debug_data_directory)
    OnError(LogWinKeyOverhaulUnhandledError)
    DebugLogSession(reason)
}

ToggleDebugLogging(*)
{
    global debug_enabled

    if debug_enabled {
        DebugLogSession("disabled")
        OnError(LogWinKeyOverhaulUnhandledError, 0)
        debug_enabled := false
    } else {
        debug_enabled := true
        InitializeDebugLogging("enabled")
    }

    UpdateDebugMenu()
}

UpdateDebugMenu()
{
    global debug_enabled

    if debug_enabled
        A_TrayMenu.Check("Debug logging")
    else
        A_TrayMenu.Uncheck("Debug logging")
}

DebugLogSession(reason)
{
    process_id := DllCall(
        "GetCurrentProcessId",
        "uint"
    )

    DebugLog(
        "Debug session " reason "."
        . " | pid=" process_id
        . " | ahk=" A_AhkVersion
        . ' | script="' A_ScriptFullPath '"'
    )
}

DebugLog(message)
{
    global debug_enabled, debug_log_path

    if !debug_enabled
        return

    timestamp := FormatTime(
        ,
        "yyyy-MM-dd HH:mm:ss"
    )

    try FileAppend(
        timestamp
        . " | tick=" A_TickCount
        . " | " message
        . "`n",
        debug_log_path,
        "UTF-8-RAW"
    )
}

; =============================================================================
; error and window diagnostics
; =============================================================================

DebugError(context, err)
{
    global debug_enabled

    if !debug_enabled
        return

    DebugLog(
        "ERROR in " context
        . " | message=" err.Message
        . " | what=" err.What
        . " | file=" err.File
        . " | line=" err.Line
    )

    if err.Stack != ""
        DebugLog(
            "STACK | "
            . StrReplace(
                StrReplace(err.Stack, "`r", ""),
                "`n",
                " | "
            )
        )
}

LogWinKeyOverhaulUnhandledError(err, mode)
{
    DebugError(
        "Unhandled error, mode=" mode,
        err
    )

    return 0
}

DebugDescribeWindow(hwnd)
{
    global debug_enabled

    if !debug_enabled
        return ""

    if !hwnd
        return "hwnd=0"

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return "hwnd=" hwnd " [invalid]"

    title := ""
    class_name := ""
    process_name := ""
    process_path := ""
    min_max := "?"
    style := "?"
    ex_style := "?"
    x := "?"
    y := "?"
    width := "?"
    height := "?"

    try title := WinGetTitle(hwnd)
    try class_name := WinGetClass(hwnd)
    try process_name := WinGetProcessName(hwnd)
    try process_path := WinGetProcessPath(hwnd)
    try min_max := WinGetMinMax(hwnd)
    try style := WinGetStyle(hwnd)
    try ex_style := WinGetExStyle(hwnd)

    try WinGetPos(
        &x,
        &y,
        &width,
        &height,
        hwnd
    )

    title := StrReplace(
        StrReplace(title, "`r", " "),
        "`n",
        " "
    )

    visible :=
        DllCall(
            "IsWindowVisible",
            "ptr", hwnd,
            "int"
        )

    iconic :=
        DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        )

    owner :=
        DllCall(
            "GetWindow",
            "ptr", hwnd,
            "uint", 4,
            "ptr"
        )

    cloaked := false

    try cloaked :=
        IsWinKeyOverhaulCloaked(hwnd)

    return (
        "hwnd=" hwnd
        . ' exe="' process_name '"'
        . ' class="' class_name '"'
        . ' title="' title '"'
        . " minmax=" min_max
        . " visible=" visible
        . " iconic=" iconic
        . " cloaked=" cloaked
        . " owner=" owner
        . " style=" style
        . " exstyle=" ex_style
        . " rect=(" x "," y " "
        . width "x" height ")"
        . ' path="' process_path '"'
    )
}
