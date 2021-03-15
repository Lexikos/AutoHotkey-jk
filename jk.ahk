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

AddAhkObjects(scope) {
    
    ; **** FUNCTIONS ****
    #include funcs.ahk ; -> functions, callback_params, output_params, output_params_return
    Loop Parse functions, ' ' {
        if A_LoopField ~= '\W'  ; Disabled function
            continue
        fn_name := A_LoopField
        fn := %fn_name%
        if functions_use_lowercase_initial_letter
            fn_name := RegExReplace(fn_name, "^.", "$l0")
        ; Does fn need special handling for callbacks?
        if cbp := callback_params.DeleteProp(fn_name) {
            fn := BifCallWrapCallback.Bind(fn, cbp)
        }
        ; Does fn need special handling for OutputVars?
        else if op_array := output_params.DeleteProp(fn_name) {
            op_return := output_params_return.DeleteProp(fn_name)
            op := Map()
            loop op_array.length
                if op_array.Has(A_Index)
                    op[A_Index] := op_array[A_Index]
            op.in_count := fn.MaxParams - op.count
            fn := BifCallReturnOutputVars.Bind(fn, op, op_return)
        }
        ; Add the function
        scope.%fn_name% := fn
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

AddAhkObjects js

/*
nativeGetCb := CallbackCreate(getCb, "F")
rfn := JsRT.CreateFunction(nativeGetCb, 0)
js.test := JsRT.FromJs(rfn)
getCb(callee, isCtor, argv, argc, state) {
    loop (args := []).length := argc
        args[A_Index] := JsRT.FromJs(NumGet(argv + (A_Index-1)*A_PtrSize, "ptr"))
    D "getCb " js.Function('$', 'return $ instanceof test')(args[1])
    return JsRT.ToJs(MsgBox)
    ; if DllCall(sc._dll "\JsCallFunction", "ptr", rcb, "ptr", argv, "ushort", argc, "ptr*", &result:=0) {
        ; DllCall(sc._dll "\JsGetAndClearException", "ptr*", &excp:=0)
        ; throw JsRT.FromJs(excp)
    ; }
}
*/

JsRT.RunFile jkfile


BifCallWrapCallback(ahkfn, pn, p*) {
    static f_prop := "_f_"
    callCb(callee, isCtor, argv, argc, state) {
        ; This serves as the entry point into JS for a new AutoHotkey thread.
        idf := JsRT.JsGetPropertyIdFromName(f_prop)
        rcb := JsRT.JsGetProperty(callee, idf)
        return JsRT.JsCallFunction(rcb, argv, argc)
    }
    if p.Has(pn) {
        cb := p[pn]
        rcb := JsRT.ToJs(cb)
        if JsRT.JsGetValueType(rcb) = 6 { ; JsFunction
            ; idf := JsRT.JsGetPropertyIdFromName(f_prop)
            ; rfn := JsRT.JsGetProperty(callee, idf)
            ; if JsRT.JsGetValueType(rfn) = 0 { ; JsUndefined
                ; static nativeCallCb := CallbackCreate(callCb, "F")
                ; rfn := JsRT.JsCreateFunction(nativeCallCb, 0)
                ; JsRT.JsSetProperty(rfn, idf, rcb, false)
                ; JsRT.JsSetProperty(rcb, idf, rfn, false)
            ; }
            ; p[pn] := ComObjectFor(rfn)
            p[pn] := ComObjectFor(rcb)
        }
    }
    return ahkfn(p*)
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


JsEnum(v) {
    static getIt := js.Eval('(function(v) { return v[Symbol.iterator](); })')
    try
        it := getIt(v)
    catch
        return a => false
    return (&a) => (s := it.next()).done ? false : (a := s.value, true)
}


JsEnumProps(value, namesOrSymbols:="Names") {
    names := JsRT.FromJs(JsRT.JsGetOwnProperty%namesOrSymbols%(JsRT.ToJs(value)))
    , i := 0
    return (&a) => (++i >= names.length) ? false : (a := names.%i%, true)
}


ErrorMsg(err, mode) {
    if ComObjType(err) {
        try {
            if err.name = "SyntaxError" {
                ; Syntax errors have line, column, source and url, but not stack.
                MsgBox Format("Syntax error: {3}`n`nFile:`t{5}`nLine:`t{1:i}`nCol:`t{2:i}`nSource:`t{4}"
                    , err.line, err.column, err.message = "Syntax error" ? "" : err.message
                    , err.source, err.url),, "IconX"
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
                ; case 65406: ; No ListLines
                ; case 65407: ; No ListVars
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
    Run Format(A_IsCompiled ? '"{2}" /restart "{3}"' : '"{1}" /restart "{2}" "{3}"'
        , A_AhkPath, A_ScriptFullPath, jkfile), A_InitialWorkingDir
}
