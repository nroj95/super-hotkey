WW_DebugLog(message) => SuiteState.Log.Debug("Wonder Windows", message)

WW_DebugError(context, failure) => SuiteState.Log.Error("Wonder Windows / " context, failure)

WW_DebugDescribeWindow(hwnd)
{
    if !SuiteState.Log.verbose
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
        IsWindowCloaked(hwnd)

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
