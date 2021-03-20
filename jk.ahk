JKVersion := '3.0-alpha.1'

; Configuration
functions_use_lowercase_initial_letter := true

; Required libraries
#include ..\ActiveScript\JsRT.ahk
#include GetCommandLineArgs.ahk
#include <D>

#NoTrayIcon
#SingleInstance Off
OnError ErrorMsg
RemoveAhkMenus

; Process command line
ParseCommandLine
ParseCommandLine() {
    global default_script_encoding := "UTF-8"
    global J_Args := GetCommandLineArgs() ; Get all, including those processed by AutoHotkey.
    global is_restart := false
    global ErrorStdOut := false
    drop_jk_ahk := !A_IsCompiled
    J_Args.RemoveAt 1 ; Drop the exe.
    loop {
        if J_Args[1] ~= 'i)^/r(?:estart)$'
            is_restart := true
        else if J_Args[1] ~= 'i)^/cp\d+$'
            default_script_encoding := SubStr(J_Args[1], 2)
        else if J_Args[1] ~= 'i)^/ErrorStdOut(?:=|$)'
            ErrorStdOut := FileOpen('**', 'w', SubStr(J_Args[1], 14))
        else if J_Args[1] ~= 'i)^/Debug(?:=|$)' && drop_jk_ahk
        {}
        else if drop_jk_ahk && J_Args[1] ~= 'i)(?:[\\/]|^)\Q' A_ScriptName '\E$'
            drop_jk_ahk := false
        else
            break
        J_Args.RemoveAt 1
    } until J_Args.Length = 0
    jkfile_found := false
    Loop Files J_Args.Length ? (jkfile := J_Args.RemoveAt(1)) : "test.jk" {
        jkfile := A_LoopFileFullPath
        jkfile_found := true
    }
    if jkfile = "" {
        MsgBox 'A script file must be specified on the command line or by drag-dropping it onto the program file. The program will now exit.',, 'Iconi'
        ExitApp
    }
    if !jkfile_found {
        MsgBox "Script file not found.",, "IconX"
        ExitApp
    }
    global J_ScriptFullPath := jkfile
}

WinSetTitle jktitle := J_ScriptFullPath ' - AutoHotkey v' JKVersion, A_ScriptHwnd
if is_restart
    TerminatePreviousInstance 'Reload'
SplitPath J_ScriptFullPath, &J_ScriptName, &J_ScriptDir
A_IconTip := A_ScriptName := J_ScriptName

; Helpers
undefined := ComObject(0,0), null := ComObject(9,0)
jsTrue := ComObject(0xB, -1), jsFalse := ComObject(0xB, 0)
AdjustFuncName := functions_use_lowercase_initial_letter
    ? n => RegExReplace(n, '^[A-Z]+', '$l0') : n => n
AdjustPropName := AdjustFuncName
AdjustClassName := n => n

; Initialize script engine
js := JsRT.Edge()

AddAhkObjects js

; Debug
IsSet(&D) ? js.D := WrapBif(D) : %'D'% := _ => ""

loading_script := true    ; ExitApp if a SyntaxError is encountered while loading.
StartupIconTimer true

; Parse and execute the main script file.
JsRT.RunFile J_ScriptFullPath, default_script_encoding

ErrorStdOut := false      ; Use it only while loading.
loading_script := false   ; Consider the loading phase complete.
StartupIconTimer          ; In case it hasn't run yet, fire and delete the timer to allow the script to exit if non-persistent.


AddAhkObjects(scope) {
    defProp := scope.Object.defineProperty
    
    ; **** FUNCTIONS ****
    #include funcs.ahk ; -> functions, callback_params, output_params, output_params_return
    Loop Parse functions, ' ' {
        if A_LoopField ~= '\W'  ; Disabled function
            continue
        fn_name := A_LoopField
        fn := %fn_name%
        ; Add the function
        fn_name := AdjustFuncName(fn_name)
        scope.%fn_name% := WrapBif(fn)
    }
    scope.%AdjustFuncName('CollectGarbage')% := WrapBif(JsRT.JsCollectGarbage.Bind(JsRT, JsRT._runtime))
    
    ; **** CLASSES ****
    Gui.Prototype.Control := Gui.Prototype.GetOwnPropDesc('__Item').get
    for cls in [Buffer, ClipboardAll, File, Gui, InputHook, Menu, MenuBar]
        scope.%cls.Prototype.__class% := WrapClass(cls)
    
    ; **** VARIABLES ****
    GetLineFile   := js.Function('return          /\((.+?:.+?):(\d+):\d+\)/.exec(Error().stack)[1];')
    GetLineNumber := js.Function('return parseInt(/\((.+?:.+?):(\d+):\d+\)/.exec(Error().stack)[2]);')
    #include vars.ahk
    defProp scope, 'A_Args', {value: js.Array(J_Args*), writable: true}
    variables.TrayMenu := JsRT.FromJs(ObjectToJs(A_TrayMenu))
    get_var(name)        => %name%
    set_var(name, value) => %name% := value
    for name, value in variables.OwnProps() {
        defProp scope, 'A_' name, value is readable ? {
            get:                          get_var.Bind('A_' name),
            set: value is readwriteable ? set_var.Bind('A_' name) : undefined
        } : value is Object ? value : {value: value}
    }
    
    ; **** REPLACEMENTS FOR DIRECTIVES ***
    for fn in [Include, InstallKeybdHook, InstallMouseHook, Persistent, SingleInstance]
        scope.%AdjustFuncName(fn.Name)% := WrapBif(fn)
}


WrapBif(fn) {
    ; Does fn need special handling for OutputVars?
    if op_array := fn.DeleteProp('output') {
        op_return := fn.DeleteProp('returns')
        op := Map()
        loop op_array.length
            if op_array.Has(A_Index)
                op[A_Index] := op_array[A_Index]
        op.in_count := fn.MaxParams - op.count
        fn := BifCallReturnOutputVars.Bind(fn, op, op_return)
    }
    static callbackFromJS := CallbackCreate(CallFromJS, "F")
    ; Since this is only used with built-in functions, we don't need to
    ; worry about the fact that the reference to fn will never be released
    ; (since there's no finalizer for rfn).
    ; FIXME: we're now used with BoundFunc, which should be released at some point.
    return JsRT.FromJs(JsRT.JsCreateFunction(callbackFromJS, ObjPtrAddRef(fn)))
}


CallFromJS(callee, isCtor, argv, argc, state) {
    try {
        fn := ObjFromPtrAddRef(state)
        if isCtor & 0xff
            throw TypeError(fn.Name ' is not a constructor')
        if JsRT.JsGetValueType(NumGet(argv, "ptr")) = 0 ; this === undefined
            argv += A_PtrSize, argc -= 1 ; Don't pass this as a parameter.
        args := ArrayFromArgv(argv, argc)
        if HasProp(fn, 'belongsTo') && not HasBase(args[1], fn.belongsTo)
            throw TypeError("'this' is not a " fn.belongsTo.__Class) ; More authentic than the default error.
        return ToJs(fn(args*))
    } catch e {
        JsRT.JsSetException ErrorToJs(e)
        return 0
    }
}


CallClassFromJS(callee, isCtor, argv, argc, state) {
    try {
        this := NumGet(argv, "ptr"), cls := ObjFromPtrAddRef(state)
        if !(isCtor & 0xff)
            throw TypeError(cls.Prototype.__Class ' cannot be called without the new keyword')
        if !JsRT.JsInstanceOf(this, callee)
            throw TypeError("'this' is not a " cls.Prototype.__Class)
        return ObjectToJs(cls(ArrayFromArgv(argv + A_PtrSize, argc - 1)*))
    } catch e {
        if e is ValueError && cls.Call = Object.Call
            e := TypeError(cls.Prototype.__Class " cannot be instantiated directly")
        JsRT.JsSetException ErrorToJs(e)
        return 0
    }
}


WrapClass(acls) {
    static jsClassFor := Map()
    if ObjHasOwnProp(acls, '__js')
        return acls.__js
    static callbackFromJS := CallbackCreate(CallClassFromJS, "F")
    jcls := JsRT.FromJs(rjcls := JsRT.JsCreateFunction(callbackFromJS, ObjPtrAddRef(acls)))
    acls          .__js := jcls
    acls.Prototype.__js := jcls.prototype
    WrapMethods acls          , jcls
    WrapMethods acls.Prototype, jcls.prototype
    if acls.base != Object {
        JsRT.JsSetPrototype(rjcls, JsRT.ToJs(jb := WrapClass(acls.base)))
        JsRT.JsSetPrototype(JsRT.ToJs(jcls.prototype), JsRT.ToJs(jb.prototype))
    }
    static setTag := js.Function('obj', 'tag', 'obj[Symbol.toStringTag] = tag')
    setTag jcls.prototype, acls.Prototype.__Class
    return jcls
}


WrapMethods(aobj, jobj) {
    defProp := js.Object.defineProperty
    for p in aobj.OwnProps() {
        if SubStr(p, 1, 2) = '__' {
            if p = '__Enum'
                SetIterator jobj, aobj.%p%
            continue
        }
        pd := aobj.GetOwnPropDesc(p)
        for name, value in pd.OwnProps()
            if value is Func
                value.belongsTo := aobj
        if pd.HasProp('value') {
            if pd.value is Func {
                pd.value := WrapBif(pd.value)
                p := AdjustFuncName(p)
            }
            else if pd.value is Class {
                pd.value := WrapClass(pd.value)
                p := AdjustClassName(p)
            }
            else ; Could be __Class or Prototype.
                continue ; No other value properties are wanted at the moment.
        }
        else if pd.HasProp('call') {
            pd := {value: WrapBif(pd.call)}
            p := AdjustFuncName(p)
        }
        else {
            if pd.HasProp('get')
                pd.get := WrapBif(pd.get)
            if pd.HasProp('set')
                pd.set := WrapBif(pd.set)
            p := AdjustPropName(p)
        }
        pd.enumerable := true
        defProp jobj, p, pd
    }
}


SetIterator(jobj, f) {
    static setIt := js.Function('v', 'f', 'v[Symbol.iterator] = f')
    get_iterator(f, this) {
        next(f, this) {
            o := js.Object()
            if (o.done := f(&v) ? jsFalse : jsTrue) = jsFalse ; true means continue for AutoHotkey, finished for JS.
                o.value := v
            return o
        }
        proto := js.Object()
        proto.next := WrapBif(next.Bind(f(this, 1)))
        return proto
    }
    setIt jobj, WrapBif(get_iterator.Bind(f))
}


ArrayFromArgv(argv, argc) {
    loop (args := []).Length := argc {
        v := NumGet(argv + (A_Index-1)*A_PtrSize, "ptr")
        switch JsRT.JsGetValueType(v) {
            case 0: ; JsUndefined
                continue ; Leave args[A_Index] unset.
            case 1: ; JsNull
                throw TypeError("Invalid use of null")
            case 4: ; JsBoolean
                v := JsRT.JsBooleanToBool(v) ; Avoids VT_BOOL representation of true as -1.
            case 5: ; JsObject
                v := ObjectFromJs(v)
            case 6: ; JsFunction
                v := JsFunctionProxy(v) ; May return an existing proxy if v has one.
            case 8: ; JsArray
                v := [ValuesOf(JsRT.FromJs(v))*]
            default:
            ; case 2: ; JsNumber
            ; case 3: ; JsString
            ; case 7: ; JsError
            ; case 9: ; JsSymbol
                v := JsRT.FromJs(v)
        }
        args[A_Index] := v
    }
    return args
}


ObjectToJs(v) {
    if ObjHasOwnProp(v, '__rj')
        return v.__rj
    if ObjHasOwnProp(b := ObjGetBase(v), '__js') {
        static finalizer := CallbackCreate(p => ObjFromPtr(p).DeleteProp('__rj'), 'F', 1)
        rj := JsRT.JsCreateExternalObject(ObjPtrAddRef(v), finalizer)
        JsRT.JsSetPrototype(rj, JsRT.ToJs(b.__js))
        return v.__rj := rj
    }
    if b = Object.prototype {
        jv := js.Object()
        for pn, pv in ObjOwnProps(v)
            jv.%pn% := pv
        return JsRT.ToJs(jv)
    }
    D 'no conversion for ' type(v)
    return JsRT.ToJs(v)
}


ToJs(v) {
    if v is Object
        return ObjectToJs(v)
    return JsRT.ToJs(v)
}


ErrorToJs(e) {
    if not e is Error
        return JsRT.ToJs(e)
    if e is TypeError
        return JsRT.JsCreateTypeError(JsRT.ToJs(StrReplace(e.message, "a ComO", "an o")))
    if e is MemberError && RegExMatch(e.message, 'named "(.*?)"', &m)
        return JsRT.JsCreateTypeError(JsRT.ToJs("Object doesn't support property or method '" m.1 "'"))
    ; FIXME: add Error functions to script for instanceof, and set prototype
    je := JsRT.JsCreateError(JsRT.ToJs(e.message))
    JsRT.FromJs(je).name := type(e)
    return je
}


ObjectFromJs(rj) {
    if JsRT.JsHasExternalData(rj)
        return ObjFromPtrAddRef(JsRT.JsGetExternalData(rj))
    return JsRT.FromJs(rj)
}


ExternalProperty(rv, name, ptr:=unset) {
    id := JsRT.JsGetPropertyIdFromName(name)
    rx := JsRT.JsGetProperty(rv, id)
    if JsRT.JsGetValueType(rx) = 0 { ; JsUndefined
        if !IsSet(&ptr) || !ptr
            return 0
        rx := JsRT.JsCreateExternalObject(ptr, 0)
        JsRT.JsSetProperty(rv, id, rx, true)
    }
    else if IsSet(&ptr)
        JsRT.JsSetExternalData(rx, ptr)
    else
        ptr := JsRT.JsGetExternalData(rx)
    return ptr
}


class JsObjectProxyBase {
    static Call(rj) {
        if p := ExternalProperty(rj, '__p')
            return ObjFromPtrAddRef(p)
        return super(rj)
    }
    __New(rj) {
        this.__j := JsRT.FromJs(rj)
        this.__rj := rj
        ; If a function is passed to SetTimer, OnMessage, etc. twice, it needs to
        ; be the same proxy object both times.  Built-in COM support would just
        ; create a new ComObject wrapper, which wouldn't allow an existing timer
        ; or callback to be deleted/unregistered.
        ; The naive approach is to create a ComObject once and store it in the JS
        ; object; but that creates a circular reference and prevents the objects
        ; from ever being deleted.  Instead, store an uncounted reference.
        ExternalProperty rj, '__p', ObjPtr(this)
    }
    __Delete() {
        ; If the proxy is deleted, that means the program hasn't kept a reference
        ; to it, so it's okay for any future calls to pass a new proxy object.
        ; __p must be cleared because the JS object might still be referenced by
        ; the script (if it's not, this.__j was keeping it alive).
        ExternalProperty this.__rj, '__p', 0
    }
}


class JsFunctionProxy extends JsObjectProxyBase {
    Call(params*) => (this.__j)(params*)
    MinParams => 0
    MaxParams => 0
    IsVariadic => true
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
        o.%name% := %p[i]%       ; Put output values into JS object.  Currently does not wrap objects, since p[i] is never an object for the currently enabled BIFs.
    return opr ? opr(r, o) : o   ; Return JS object, allowing variations to be handled by opr.
}


ValuesOf(v) {
    static getIt := js.Function('v', 'return v[Symbol.iterator]()')
    it := getIt(v)
    return (&a) => (s := it.next()).done ? false : (a := s.value, true)
}


ErrorMsg(err, mode) {
    if ComObjType(err) {
        try {
            if err.name = "SyntaxError" {
                ; Syntax errors have message, line, column, url and source.
                if ErrorStdOut
                    ErrorStdOut.WriteLine(Format("{1} ({2:i}) : ==> {3}`n     Specifically: {4}"
                        , err.url, err.line, err.message, err.source))
                else
                    MsgBox Format("Syntax error: {1}`n`nFile:`t{2}`nLine:`t{3:i}`nCol:`t{4:i}`nSource:`t{5}"
                        , err.message = "Syntax error" ? "" : err.message
                        , err.url, err.line, err.column, err.source),, "IconX"
                if loading_script
                    ExitApp 2
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
    if WinExist(J_ScriptName,, WinGetTitle(A_ScriptHwnd))
        return WinActivate()
    try
        Run '*edit "' J_ScriptFullPath '"'
    catch
        Run 'notepad.exe "' J_ScriptFullPath '"'
}


Reload() {
    Run Format(A_IsCompiled ? '"{2}" /restart "{3}"' : '"{1}" "{2}" /restart "{3}"'
        , A_AhkPath, A_ScriptFullPath, J_ScriptFullPath), A_InitialWorkingDir
}


SingleInstance(mode:='force') {
    switch StrLower(mode) {
        case 'force':
            TerminatePreviousInstance 'SingleInstance'
        case 'ignore':
            for hwnd in WinGetList(jktitle " ahk_class AutoHotkey")
                if hwnd != A_ScriptHwnd
                    ExitApp
        default:
            throw ValueError('Invalid mode "' mode '"')
    }
}


Include(path) {
    static already_included := (_ => (_.CaseSense := 'Off', _))(Map())
    included := 0
    Loop Files path, 'F' {
        path := A_LoopFileFullPath
        if already_included.Has(path)
            continue
        already_included[path] := true
        JsRT.RunFile path, default_script_encoding
        ++included
    }
    if !included && !(path ~= '[*?]')
        throw Error('Include file "' path '" cannot be opened.')
}


Persistent() {
    OnMessage(0xBADC0DE, (*) => "")
}


InstallKeybdHook() {
    static ih
    if IsSet(&ih)
        return
    ih := InputHook('I255 L0 B V')
    ih.Start
}


InstallMouseHook() {
    ; If a custom combination uses the same key as both prefix and suffix,
    ; it will never execute.  Even if it did, it would have no effect and
    ; is unlikely to conflict with an existing hotkey for obvious reasons.
    Hotkey '~XButton2 & ~XButton2', _ => 0
    ; Note: To undo this later, it's necessary to know which HotIf context
    ; was active, and currently that's impossible unless you set it yourself.
    ; To do this without affecting the caller's HotIf, create a new thread.
}


StartupIconTimer(enable := unset) {
    ; This timer is used to prevent the icon from appearing momentarily
    ; for scripts which use A_IconHidden within 100ms of starting.
    if !IsSet(&enable) {
        if !IconTimerIsSet ; Timer already fired or script has set A_IconHidden.
            return
        A_IconHidden := false
        enable := false
    }
    global IconTimerIsSet := enable
    SetTimer StartupIconTimer, enable ? -100 : 0
}
GetIconHidden() => A_IconHidden && !IconTimerIsSet
SetIconHidden(value) {
    A_IconHidden := value
    StartupIconTimer false
}


TerminatePreviousInstance(by) {
    DetectHiddenWindows (dhw := A_DetectHiddenWindows, true)
    for hwnd in WinGetList(jktitle " ahk_class AutoHotkey") {
        if hwnd != A_ScriptHwnd {
            TerminateInstance hwnd, by
            break
        }
    }
    DetectHiddenWindows dhw
}

TerminateInstance(hwnd, by) {
    static WM_COMMNOTIFY := 0x44
    static AHK_EXIT_BY_RELOAD := 1030
    static AHK_EXIT_BY_SINGLEINSTANCE := 1031
    PostMessage WM_COMMNOTIFY, AHK_EXIT_BY_%by%, 0, hwnd
    Loop {
        if WinWaitClose(hwnd,, 2)
            break
        if MsgBox("Could not close the previous instance of this script.  Keep waiting?",, "y/n") = "no"
            ExitApp 2
    }
}
