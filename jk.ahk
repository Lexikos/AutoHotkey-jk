JKVersion := '3.0-alpha.1'

; Configuration
functions_use_lowercase_initial_letter := true

; Required libraries
#include ..\ActiveScript\JsRT.ahk
#include <D>

#SingleInstance Off
OnError ErrorMsg
RemoveAhkMenus

; Avoid briefly showing the icon when A_IconHidden=true is present.
; FIXME: prevent the timer from overriding JS use of A_IconHidden.
; #NoTrayIcon
; SetTimer () => A_IconHidden := false, -50

; Process command line
jkfile := ""
Loop Files A_Args.Length ? A_Args[1] : "test.jk"
    jkfile := A_LoopFileFullPath
if jkfile = "" {
    MsgBox 'A script file must be specified on the command line or by drag-dropping it into the program file. The program will now exit.',, 'Iconi'
    ExitApp
}
WinSetTitle jkfile ' - AutoHotkey v' JKVersion, A_ScriptHwnd
; TODO: #SingleInstance replacement? /restart replacement?

; Helpers
undefined := ComObject(0,0)
Object.Prototype.toString := this => Format("[{1} object]", type(this))

; Initialize script engine
js := JsRT.Edge()

AddAhkObjects js

JsRT.RunFile jkfile


AddAhkObjects(scope) {
    
    ; **** FUNCTIONS ****
    #include funcs.ahk ; -> functions, callback_params, output_params, output_params_return
    adjust_name := functions_use_lowercase_initial_letter
        ? n => RegExReplace(n, '^.', '$l0') : n => n
    Loop Parse functions, ' ' {
        if A_LoopField ~= '\W'  ; Disabled function
            continue
        fn_name := A_LoopField
        fn := %fn_name%
        ; Does fn need special handling for OutputVars?
        if op_array := output_params.DeleteProp(fn_name) {
            op_return := output_params_return.DeleteProp(fn_name)
            op := Map()
            loop op_array.length
                if op_array.Has(A_Index)
                    op[A_Index] := op_array[A_Index]
            op.in_count := fn.MaxParams - op.count
            fn := BifCallReturnOutputVars.Bind(fn, op, op_return)
        }
        ; Add the function
        fn_name := adjust_name(fn_name)
        scope.%fn_name% := WrapBif(fn)
    }
    
    ; **** VARIABLES ****
    #include vars.ahk
    get_var(name)        => %name%
    set_var(name, value) => %name% := value
    defProp := scope.Object.defineProperty
    for name, value in variables.OwnProps() {
        defProp scope, 'A_' name, value is readable ? {
            get:                          get_var.Bind('A_' name),
            set: value is readwriteable ? set_var.Bind('A_' name) : undefined
        } : value is Object ? value : {value: value}
    }
    
    ; **** CLASSES ****
    for cls in [Buffer, ClipboardAll, File, Gui, InputHook, Menu, MenuBar]
        scope.%cls.Prototype.__class% := cls
    
    ; Much more needs to be done for classes to work properly.
    ; "new cls()" returns cls.prototype itself (probably a JsRT bug?).
    ; If cls is replaced with a JS function which just calls the real
    ; class, "x = new cls()" works but "x instanceof cls" is false.
    ; instanceof requires a true JS function.
    ; Probably need to reconstruct the class in JS, as wrappers.
    ;  - AHK method names are case-insensitive, breaking the illusion
    ;    that JS is implemented natively.
    ;  - Methods like OnEvent can't deregister a function because it
    ;    will have a different ComObject wrapper for each call.
    ;  - Native AHK Object methods will be available, not native JS ones.
    ;  - A few methods might return an AHK Object/Array/Map.
    ;  - ... more?
}


WrapBif(fn) {
    static callbackFromJS := CallbackCreate(CallFromJS, "F")
    ; Since this is only used with built-in functions, we don't need to
    ; worry about the fact that the reference to fn will never be released
    ; (since there's no finalizer for rfn).
    return JsRT.FromJs(JsRT.JsCreateFunction(callbackFromJS, ObjPtrAddRef(fn)))
}


CallFromJS(callee, isCtor, argv, argc, state) {
    try {
        if JsRT.JsGetValueType(NumGet(argv, "ptr")) = 0 ; this === undefined
            argv += A_PtrSize, argc -= 1 ; Don't pass this as a parameter.
        return JsRT.ToJs(ObjFromPtrAddRef(state)(ConvertArgv(argv, argc)*))
    } catch e {
        JsRT.JsSetException(e is Error ? ErrorToJs(e) : JsRT.ToJs(e))
        return 0
    }
}


ConvertArgv(argv, argc) {
    loop (args := []).Length := argc {
        v := NumGet(argv + (A_Index-1)*A_PtrSize, "ptr")
        switch JsRT.JsGetValueType(v) {
            case 0: ; JsUndefined
                continue ; Leave args[A_Index] unset.
            case 1: ; JsNull
                throw TypeError("Invalid use of null")
            case 4: ; JsBoolean
                v := JsRT.JsBooleanToBool(v) ; Avoids VT_BOOL representation of true as -1.
            case 6: ; JsFunction
                v := ComObjectFor(v) ; Always returns the same ComObject for a given JS object.
            default:
            ; case 2: ; JsNumber
            ; case 3: ; JsString
            ; case 5: ; JsObject
            ; case 7: ; JsError
            ; case 8: ; JsArray
            ; case 9: ; JsSymbol
                v := JsRT.FromJs(v)
        }
        args[A_Index] := v
    }
    return args
}


ErrorToJs(e) {
    if e is TypeError
        return JsRT.JsCreateTypeError(JsRT.ToJs(StrReplace(e.message, "a ComO", "an o")))
    if e is MemberError && RegExMatch(e.message, 'named "(.*?)"', &m)
        return JsRT.JsCreateTypeError(JsRT.ToJs("Object doesn't support property or method '" m.1 "'"))
    ; FIXME: add Error functions to script for instanceof, and set prototype
    je := JsRT.JsCreateError(JsRT.ToJs(e.message))
    JsRT.FromJs(je).name := type(e)
    return je
}


ComObjectFor(rv) {
    static x_prop := "_x_"
    idx := JsRT.JsGetPropertyIdFromName(x_prop)
    rx := JsRT.JsGetProperty(rv, idx)
    if JsRT.JsGetValueType(rx) = 0 { ; JsUndefined
        obj := JsRT.FromJs(rv)
        static finalizer := CallbackCreate(ObjRelease, "F", 1)
        rx := JsRT.JsCreateExternalObject(ObjPtrAddRef(obj), finalizer)
        JsRT.JsSetProperty(rv, idx, rx, true)
    } else {
        pobj := JsRT.JsGetExternalData(rx)
        obj := ObjFromPtrAddRef(pobj)
    }
    return obj
}


BifCallReturnOutputVars(ahkfn, op, opr, p*) {
    MakeRef(s:='') => &s
    if p.length < op.in_count
        p.length := op.in_count  ; Allow inserting at positions beyond original p.length.
    for i in op
        p.InsertAt i, MakeRef()  ; Insert VarRefs into OutputVar positions.
    r := ahkfn(p*)               ; Call original function.
    o := js.Object()
    for i, name in op
        o.%name% := %p[i]%       ; Put output values into JS object.
    return opr ? opr(r, o) : o   ; Return JS object, allowing variations to be handled by opr.
}


ErrorMsg(err, mode) {
    if ComObjType(err) {
        try {
            if err.name = "SyntaxError" {
                ; Syntax errors have message, line, column, url and source.
                MsgBox Format("Syntax error: {1}`n`nFile:`t{2}`nLine:`t{3:i}`nCol:`t{4:i}`nSource:`t{5}"
                    , err.message = "Syntax error" ? "" : err.message
                    , err.url, err.line, err.column, err.source),, "IconX"
            } else {
                ; Runtime errors have stack, which includes the error name and message.
                MsgBox err.stack,, "IconX"
            }
            return true
        }
    }
    try {
        stack := "", specifically := ""
        try (!A_IsCompiled) && stack := '`n`n' RegExReplace(err.stack, 'm)^.*?\\(?=[^\\]* \(\d+\) :)', '')
        try (err.extra != "") && specifically := "`n`nSpecifically: " err.extra
        MsgBox err.message specifically stack,, "IconX"
    } catch {
        try {
            try value := err.toString()
            catch
            try value := String(err)
            catch
                value := err
        }
        MsgBox "Value thrown and not caught.`n`nSpecifically: " value,, "IconX"
    }
    return true
}


RemoveAhkMenus() {
    hmenu := DllCall("GetMenu", "ptr", A_ScriptHwnd)
    DllCall("RemoveMenu", "ptr", hmenu, "uint", 65406, "uint", 0)
    DllCall("RemoveMenu", "ptr", hmenu, "uint", 65407, "uint", 0)
    
    static newproc := CallbackCreate(WindowProc, "F", 4)
    static oldproc := DllCall("SetWindowLong" (A_PtrSize=8 ? "PtrW" : "W")
        , "ptr", A_ScriptHwnd, "int", -4, "ptr", newproc, "ptr")
    WindowProc(hwnd, nmsg, wParam, lParam) {
        if (nmsg = 0x111 && (wParam & 0xFFFF) >= 65300) {
            switch wParam & 0xFFFF {
                case 65406: (A_IsCompiled) || ListLines() ; Allow for debug when not compiled.
                case 65407: (A_IsCompiled) || ListVars()
                case 65400, 65303: Reload
                case 65401, 65304: Edit
                case 65300: ; Open
                    if A_AllowMainWindow
                        WinShow A_ScriptHwnd
                default: goto default_action ; Allow all others
            }
            return 0
        }
        default_action:
        return DllCall("CallWindowProc", "ptr", oldproc, "ptr", hwnd, "uint", nmsg, "ptr", wParam, "ptr", lParam)
    }
}

Edit() {
    SplitPath jkfile, &fn
    if WinExist(fn,, WinGetTitle(A_ScriptHwnd))
        return WinActivate()
    try
        Run '*edit "' jkfile '"'
    catch
        Run 'notepad.exe "' jkfile '"'
}

Reload() {
    ; FIXME: new instance might close wrong old instance if multiple jk files are running
    Run Format(A_IsCompiled ? '"{2}" /restart "{3}"' : '"{1}" /restart "{2}" "{3}"'
        , A_AhkPath, A_ScriptFullPath, jkfile), A_InitialWorkingDir
}
