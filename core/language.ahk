; =============================================================================
; Translations. Code writes visible text in English inside T("..."), and
; guides one sentence per line; lang\<code>.lang turns that English into
; another language. Text a file leaves out shows in English, and a missing or
; damaged file leaves the whole suite in English, so a half-finished
; translation never breaks a page.
;
; The launcher loads one language at startup, before any action or page is
; built, so a choice on the Language page restarts the suite. T() must
; run when its text is shown or registered, never in a static initializer,
; which runs before the language loads. Checks never load one: they run in
; English.
;
; A .lang file is UTF-8 text that tools/lang.py keeps current:
;   ; language: Norsk bokmål    the name the Language page lists
;   English text                exactly as written in the code, escapes included
;   = Norsk tekst               nothing after "=" means not translated yet
; Other lines starting with ";" are comments; blank lines separate entries.
; =============================================================================

; text in the suite's language; values fill {1}, {2}... as in Format.
T(text, values*) {
    text := SuiteLanguage.Text(text)
    return values.Length ? Format(text, values*) : text
}

class SuiteLanguage {
    static Folder := A_ScriptDir "\lang"
    static English := "English"
    static code := "en"
    static texts := Map()

    ; For text that is not a literal, such as a guide's lines.
    static Text(text) => this.texts.Get(text, text)

    ; choice: a file's code, "en", or "" to follow the Windows display language.
    static Load(choice) {
        code := choice != "" ? choice : this.Detect()
        if code = "en" {
            SuiteState.Log.Write("Core", "language: " SuiteLanguage.English)
            return
        }
        try {
            language := this.Read(this.Folder "\" code ".lang")
            this.code := code
            this.texts := language.texts
            SuiteState.Log.Write("Core", "language: " code " (" language.name ")")
        }
        catch Error as failure
            SuiteState.Log.Error("Core / language " code, failure)
    }

    ; The Windows display language's file, nb-NO.lang before nb.lang, or "en".
    static Detect() {
        name := Buffer(170, 0) ; LOCALE_NAME_MAX_LENGTH characters
        if !DllCall("LCIDToLocaleName", "uint", DllCall("GetUserDefaultUILanguage", "ushort"),
            "ptr", name, "int", 85, "uint", 0, "int")
            return "en"
        locale := StrGet(name)
        for code in [locale, StrSplit(locale, "-")[1]]
            if FileExist(this.Folder "\" code ".lang")
                return code
        return "en"
    }

    ; [{code, name}] of the language files, without the template.
    static Available() {
        languages := []
        loop files this.Folder "\*.lang" {
            code := SubStr(A_LoopFileName, 1, -5)
            if code = "template"
                continue
            try {
                name := this.Read(A_LoopFileFullPath).name
                languages.Push({code: code, name: name != "" ? name : code})
            }
        }
        return languages
    }

    static Read(path) {
        if FileGetSize(path) > 2 * 1024 * 1024
            throw Error("The language file exceeds the size limit: " path)
        return this.Decode(FileRead(path, "UTF-8"))
    }

    ; {name, texts}: the language line's name and a Map from English to the
    ; translation. A stray line is skipped, never fatal; tools/lang.py reports it.
    static Decode(content) {
        name := ""
        texts := Map()
        source := ""
        loop parse LTrim(content, Chr(0xFEFF)), "`n", "`r" {
            line := A_LoopField
            if RegExMatch(line, "^;\s*language:\s*(.*?)\s*$", &match)
                name := match[1]
            else if SubStr(line, 1, 1) = "=" {
                translation := RegExReplace(SubStr(line, 2), "^ ")
                if source != "" && translation != ""
                    texts[this.Unescape(source)] := this.Unescape(translation)
                source := ""
            }
            else
                source := line = "" || SubStr(line, 1, 1) = ";" ? "" : line
        }
        return {name: name, texts: texts}
    }

    ; Undoes AutoHotkey's escapes as quoted text in the code has them: `n, `r,
    ; `t and `s; any other escaped character stands for itself.
    static Unescape(text) {
        if !InStr(text, "``")
            return text
        result := ""
        escaped := false
        loop parse text {
            if escaped
                result .= A_LoopField == "n" ? "`n" : A_LoopField == "r" ? "`r"
                    : A_LoopField == "t" ? "`t" : A_LoopField == "s" ? " " : A_LoopField
            else if A_LoopField != "``"
                result .= A_LoopField
            escaped := !escaped && A_LoopField = "``"
        }
        return result
    }
}
