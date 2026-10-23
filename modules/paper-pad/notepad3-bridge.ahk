; =============================================================================
; Notepad3 / Scintilla bridge
; =============================================================================
; Verified against Notepad3 source: src/Notepad3.h (np3params, IDC_*),
; src/Notepad3.c (MsgCopyData, _SetEnumWindowsItems, MsgCommand), and
; language/common_res.h (command IDs). Native message handlers may return zero
; even on success; transport success and the resulting editor state are distinct.
;
; WM_GETTEXT and WM_COPYDATA are marshaled by Windows. Scintilla calls below carry
; integers only. There is no VirtualAllocEx, WriteProcessMemory or pointer injection.
; =============================================================================

; A changing text length is retryable before Save; corrupt/unsupported text and
; failed message transport remain ordinary hard errors.
class PaperPadTextChangedError extends Error
{
}

class Notepad3Bridge
{

    static encoding_utf8 := 40103
    static line_endings_lf := 40202
    static view_menubar := 41023
    static view_toolbar := 41024
    static minimize_to_tray := 42019
    static no_escape_action := 42027

    __New(hwnd)
    {
        this.hwnd := hwnd
        this.tainted := false
        ; One bounded WM_GETTEXT reads the filename atomically. Keep an extra
        ; character beyond the path limit so truncation is never accepted.
        this.filename_buffer := Buffer((32767 + 2) * 2, 0)
        this.cached_filename := ""
        this.cached_full_path := ""
        this.pid := WinGetPID("ahk_id " hwnd)
        this.editor_hwnd := DllCall("GetDlgItem", "ptr", hwnd, "int", 0xFB03, "ptr")
        this.filename_hwnd := DllCall("GetDlgItem", "ptr", hwnd, "int", 0xFB05, "ptr")
        if !this.editor_hwnd || !this.filename_hwnd
            throw Error("This window does not expose the expected Notepad3 controls. No document was changed.")
        if WinGetClass("ahk_id " this.editor_hwnd) != "Scintilla"
            throw Error("The Notepad3 editor control is not Scintilla. No document was changed.")
    }

    CheckReady()
    {
        if this.tainted
            throw Error("The previous Notepad3 request timed out. Resolve its dialog, then retry.")
        if !DllCall("IsWindow", "ptr", this.hwnd, "int")
            || WinGetPID("ahk_id " this.hwnd) != this.pid
            throw Error("The owned Notepad3 window is no longer available.")
        if !PaperPadWindowIdle(this.hwnd)
            throw Error("Finish or cancel the Notepad3 menu/dialog before using a Paper Pad command.")
    }

    Send(message, w_param := 0, l_param := 0, target_hwnd := 0)
    {
        if this.tainted
            throw Error("Notepad3 is still waiting on a previous request. Resolve its dialog and retry.")
        if !target_hwnd
            target_hwnd := this.hwnd
        result := Buffer(A_PtrSize, 0)
        ; SMTO_BLOCK | SMTO_ABORTIFHUNG | SMTO_ERRORONEXIT. A timeout is NOT success.
        if !DllCall("SendMessageTimeoutW", "ptr", target_hwnd, "uint", message,
            "uptr", w_param, "ptr", l_param, "uint", 0x23, "uint", 3000,
            "ptr", result, "ptr") {
            this.tainted := true
            throw Error("Notepad3 did not respond within three seconds (message " Format("0x{:X}", message)
                . "). Resolve any editor dialog, then retry. No save or close was assumed successful.")
        }
        return NumGet(result, 0, "ptr")
    }

    CurrentPath()
    {
        capacity := this.filename_buffer.Size // 2
        copied := this.Send(0x000D, capacity, this.filename_buffer.Ptr, this.filename_hwnd) ; WM_GETTEXT
        if copied < 0 || copied > 32767
            throw Error("Notepad3's current filename exceeds the supported path length.")
        path := copied ? StrGet(this.filename_buffer, copied, "UTF-16") : ""
        if StrLen(path) != copied
            throw Error("Notepad3 returned an invalid current filename.")

        ; The visible watcher reads this four times per second. Avoid two path
        ; normalization calls whenever the actual filename has not changed.
        if !(path == this.cached_filename) {
            full_path := path = "" ? "" : PaperPadFullPath(path)
            this.cached_filename := path
            this.cached_full_path := full_path
        }
        return this.cached_full_path
    }

    ReadWindowText(hwnd, limit := 16777216)
    {
        ; Standard Unicode WM_GETTEXT is marshaled by Windows. Retry a changing
        ; length briefly; a short read caused by typing is not a disk conflict.
        loop 3 {
            length := this.Send(0x000E, 0, 0, hwnd) ; WM_GETTEXTLENGTH
            if length < 0 || length > limit
                throw Error("The editor text is too large to verify automatically. Save it manually in Notepad3.")
            text_buffer := Buffer((length + 1) * 2, 0)
            copied := this.Send(0x000D, length + 1, text_buffer.Ptr, hwnd) ; WM_GETTEXT
            if copied < 0 || copied > length
                throw Error("Notepad3 returned an invalid editor text length.")
            text := copied ? StrGet(text_buffer, copied, "UTF-16") : ""
            if StrLen(text) != copied
                throw Error("The editor contains embedded NUL characters. Save it manually in Notepad3.")
            if this.Send(0x000E, 0, 0, hwnd) = length && copied = length
                return text
        }
        throw PaperPadTextChangedError("The editor kept changing while its text was being read. Retry after editing stops.")
    }

    Scintilla(message, w_param := 0, l_param := 0)
    {
        return this.Send(message, w_param, l_param, this.editor_hwnd)
    }

    IsDirty()
    {
        return this.Scintilla(2159) != 0 ; SCI_GETMODIFY
    }

    ; The fixed IDs come from Notepad3's resources. Send one only while the
    ; running editor's menu has it, so a renumbered release fails closed.
    Command(command_id)
    {
        this.CheckReady()
        this.MenuState(command_id)
        this.SendCommand(command_id)
    }

    SendCommand(command_id)
    {
        this.Send(0x0111, command_id, 0) ; WM_COMMAND, native menu command
        this.CheckReady()
    }

    Save()
    {
        ; File > Save is the third item in Notepad3's File menu.
        ; Resolve its command ID from the running editor instead of hardcoding it.
        this.SendCommand(this.MenuCommandId(0, 2))
    }

    MenuCommandId(top_level_index, item_index)
    {
        this.CheckReady()

        main_menu := DllCall("GetMenu", "ptr", this.hwnd, "ptr")
        if !main_menu
            throw Error("Notepad3's menu bar is unavailable.")

        submenu := DllCall(
            "GetSubMenu",
            "ptr", main_menu,
            "int", top_level_index,
            "ptr"
        )

        if !submenu
            throw Error("Notepad3's expected menu is unavailable.")

        command_id := DllCall(
            "GetMenuItemID",
            "ptr", submenu,
            "int", item_index,
            "uint"
        )

        if command_id = 0xFFFFFFFF
            throw Error("Notepad3's Save command could not be resolved.")

        return command_id
    }

    MenuState(command_id)
    {
        menu_handle := DllCall("GetMenu", "ptr", this.hwnd, "ptr")
        if !menu_handle
            throw Error("Show Notepad3's menu bar before retrying the Paper Pad command.")
        this.Send(0x0116, menu_handle, 0) ; WM_INITMENU refreshes dynamic check states.
        state := DllCall("GetMenuState", "ptr", menu_handle, "uint", command_id, "uint", 0, "uint")
        if state = 0xFFFFFFFF
            throw Error("Notepad3's expected menu command is missing: " command_id)
        return state
    }

    PrepareDrawer()
    {
        this.CheckReady()
        ; Keep native File/Settings menus available for saving and error recovery.
        ; A hidden menu bar cannot be inspected, so verify the result instead.
        if !DllCall("GetMenu", "ptr", this.hwnd, "ptr") {
            this.SendCommand(Notepad3Bridge.view_menubar)
            if !DllCall("GetMenu", "ptr", this.hwnd, "ptr")
                throw Error("Notepad3 did not show its menu bar. No document was changed.")
        }
        for command_id in [Notepad3Bridge.view_toolbar, Notepad3Bridge.minimize_to_tray] {
            if this.MenuState(command_id) & 8 ; MF_CHECKED
                this.Command(command_id)
        }
        ; Our Escape handler owns hiding, not Notepad3's optional Escape-to-exit.
        this.Command(Notepad3Bridge.no_escape_action)
    }

    OpenPage(path, sender_hwnd)
    {
        this.CheckReady()
        if this.IsDirty()
            throw Error("The current page became dirty during switching. It has not been replaced.")
        ; np3params is twelve 32-bit fields, then UTF-16 text at offset 48.
        ; sizeof(np3params) is 52 (tail padding), regardless of editor bitness.
        payload := Buffer(52 + StrPut(path, "UTF-16") * 2, 0)
        NumPut("int", 1, payload, 0)   ; flagFileSpecified
        NumPut("int", 2, payload, 4)   ; FWM_MSGBOX: prompt, never silently reload
        NumPut("int", -1, payload, 32) ; CPI_NONE: preserve file encoding detection
        StrPut path, payload.Ptr + 48, (payload.Size - 48) // 2, "UTF-16"
        copy_data := Buffer(3 * A_PtrSize, 0)
        NumPut("uptr", 0xFB10, copy_data, 0) ; DATA_NOTEPAD3_PARAMS
        NumPut("uint", payload.Size, copy_data, A_PtrSize)
        NumPut("ptr", payload.Ptr, copy_data, 2 * A_PtrSize)
        this.Send(0x004A, sender_hwnd, copy_data.Ptr) ; WM_COPYDATA (not PostMessage)
        ; MsgCopyData returns FALSE even on a successful load. Check the real path.
        this.CheckReady()
        if this.CurrentPath() != path
            throw Error("Notepad3 did not switch to:`n" path)
    }

    DocumentText()
    {
        this.CheckReady()
        return this.ReadWindowText(this.editor_hwnd)
    }

    MatchesDisk(path)
    {
        return this.MatchesDiskText(path, this.DocumentText())
    }

    MatchesDiskText(path, expected_text)
    {
        limit := 32 * 1024 * 1024
        if FileGetSize(path) > limit
            throw Error("This file is too large for automatic conflict comparison. Preserve both versions before continuing.")
        ; Bound the read itself too: a concurrently growing file must not bypass
        ; the limit checked above. One extra byte detects a truncated read.
        bytes := FileRead(path, "RAW m" (limit + 1))
        size := bytes.Size
        if size > limit
            throw Error("This file grew beyond the automatic comparison limit. Preserve both versions before continuing.")
        if !size
            disk_text := ""
        else if size >= 2 && NumGet(bytes, 0, "ushort") = 0xFEFF {
            if Mod(size - 2, 2)
                return false
            disk_text := StrGet(bytes.Ptr + 2, (size - 2) // 2, "UTF-16")
            if StrLen(disk_text) != (size - 2) // 2
                return false
        }
        else {
            ; Strict UTF-8 for the normal page format; BOM is not document text.
            offset := size >= 3 && NumGet(bytes, 0, "uchar") = 0xEF
                && NumGet(bytes, 1, "uchar") = 0xBB && NumGet(bytes, 2, "uchar") = 0xBF ? 3 : 0
            if size = offset
                disk_text := ""
            else {
                count := DllCall("MultiByteToWideChar", "uint", 65001, "uint", 8,
                    "ptr", bytes.Ptr + offset, "int", size - offset, "ptr", 0, "int", 0, "int")
                if !count
                    throw Error("Automatic conflict comparison supports UTF-8 and UTF-16 LE pages. This file uses another encoding. Preserve the editor text with File > Save As to a new UTF-8 Paper Pad page.")
                unicode := Buffer((count + 1) * 2, 0)
                if !DllCall("MultiByteToWideChar", "uint", 65001, "uint", 8,
                    "ptr", bytes.Ptr + offset, "int", size - offset, "ptr", unicode, "int", count, "int")
                    throw OSError(A_LastError, "MultiByteToWideChar")
                disk_text := StrGet(unicode, "UTF-16")
                if StrLen(disk_text) != count
                    return false
            }
        }
        return disk_text == expected_text
    }
}
