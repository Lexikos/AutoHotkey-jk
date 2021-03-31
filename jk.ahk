JKVersion := '3.0-alpha.1'
;@Ahk2Exe-Obey U_bits, = A_PtrSize*8
;@Ahk2Exe-SetName AutoHotkey %U_bits%-bit (jk)
;@Ahk2Exe-SetVersion %A_PriorLine~.*'(.*)'~$1%
;@Ahk2Exe-SetDescription AutoHotkey %U_bits%-bit (jk)
;@Ahk2Exe-SetCopyright Copyright (c) 2021
;@Ahk2Exe-Bin %A_ScriptDir%\bin32\AutoHotkeySC.bin, AutoHotkey32.exe
;@Ahk2Exe-Bin %A_ScriptDir%\bin64\AutoHotkeySC.bin, AutoHotkey64.exe

#Requires AutoHotkey v2.0-a128+

; Configuration
functions_use_lowercase_initial_letter := true
allow_wildcard_in_include := false

; Required libraries
#include ..\ActiveScript\JsRT.ahk
#include GetCommandLineArgs.ahk
;@Ahk2Exe-IgnoreBegin
#include *i <D>
;@Ahk2Exe-IgnoreEnd


#NoTrayIcon
#SingleInstance Off
OnError ErrorMsg
A_AllowMainWindow := true
PatchMenus

; Process command line
ParseCommandLine
ParseCommandLine() {
    global default_script_encoding := "UTF-8"
    global J_Args := GetCommandLineArgs() ; Get all, including those processed by AutoHotkey.
    global is_restart := false
    global ErrorStdOut := false
    drop_jk_ahk := !A_IsCompiled
    J_Args.RemoveAt 1 ; Drop the exe.
    while J_Args.Length {
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
    }
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
SetWorkingDir J_ScriptDir

; Helpers
undefined := ComObject(0,0), null := ComObject(9,0)
jsTrue := ComObject(0xB, -1), jsFalse := ComObject(0xB, 0)
AdjustFuncName := functions_use_lowercase_initial_letter
    ? n => RegExReplace(n, '^[A-Z]+', '$l0') : n => n
AdjustPropName := AdjustFuncName
AdjustMethodName := AdjustFuncName
AdjustClassName := n => n

; Initialize script engine
js := JsRT.Edge()

MIN_SAFE_INTEGER := js.Number.MIN_SAFE_INTEGER
MAX_SAFE_INTEGER := js.Number.MAX_SAFE_INTEGER

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
    Hotkey := _Hotkey ; Define this locally so it will be used below.
    Boolean(r) => r ? jsTrue : jsFalse
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
    AddHotkeySettings(scope)
    
    ; **** CLASSES ****
    Gui.Prototype.Control := Gui.Prototype.GetOwnPropDesc('__Item').get
    for cls in [ClipboardAll, File, Gui, InputHook, Menu, MenuBar]
        scope.%cls.Prototype.__class% := WrapClass(cls)
    for cls in [MemoryError, OSError, TargetError, TimeoutError]
        scope.%cls.Prototype.__class% := WrapErrorClass(cls)
    
    ; **** VARIABLES ****
    GetLineFile   := js.Function('return          /\((.+?:.+?):(\d+):\d+\)/.exec(Error().stack)[1];')
    GetLineNumber := js.Function('return parseInt(/\((.+?:.+?):(\d+):\d+\)/.exec(Error().stack)[2]);')
    #include vars.ahk
    defProp scope, 'A_Args', {value: js.Array(J_Args*), writable: true}
    variables.Clipboard := {
        get: () => A_Clipboard,
        set: (value) => A_Clipboard := IsObject(value) ? ObjectFromJs(JsRT.ToJs(value)) : value
    }
    variables.TrayMenu := JsRT.FromJs(ObjectToJs(J_TrayMenu))
    defProp variables.TrayMenu, AdjustMethodName('Show'), {value: WrapBif(TrayMenu_Show_Fix)}
    get_var(name)        => %name%
    set_var(name, value) => %name% := value
    for name, value in variables.OwnProps() {
        defProp scope, 'A_' name, value is readable ? {
            get:                          get_var.Bind('A_' name),
            set: value is readwriteable ? set_var.Bind('A_' name) : undefined
        } : value is Object ? value : {value: value}
    }
    
    ; **** REPLACEMENTS FOR DIRECTIVES ***
    Persistent(n:=true) {
        global Persistent
        static isPersistent
        if IsSet(&Persistent) && Persistent is Func
            wasPersistent := Persistent(n) ; v2.0-a130+
        else {
            wasPersistent := isPersistent
            OnMessage(0xBADC0DE, (*) => "", isPersistent := n) ; v2.0-a129 and older
        }
        return wasPersistent ? jsTrue : jsFalse
    }
    for fn in [Include, InstallKeybdHook, InstallMouseHook, Persistent, SingleInstance]
        scope.%AdjustFuncName(fn.Name)% := WrapBif(fn)
    
    ; **** REPLACEMENTS FOR LOOPS ***
    scope.%AdjustFuncName('LoopFiles')% := WrapBif(_LoopFiles)
    scope.%AdjustFuncName('LoopReg')% := WrapBif(_LoopReg)
    
    ; **** Additional Functions ***
    scope.%AdjustFuncName('CollectGarbage')% := WrapBif(JsRT.JsCollectGarbage.Bind(JsRT, JsRT._runtime))
}


WrapBif(fn) {
    ; Does fn need special handling?
    op_return := fn.DeleteProp('returns')
    if op_array := fn.DeleteProp('output') {
        op := Map()
        loop op_array.length
            if op_array.Has(A_Index)
                op[A_Index] := op_array[A_Index]
        op.in_count := fn.MaxParams - op.count
        fn := BifCallReturnOutputVars.Bind(fn, op, op_return)
    }
    else if op_return {
        fn := ((r, fn, p*) => r(fn(p*))).Bind(op_return, fn)
    }
    static callbackFromJS := CallbackCreate(CallFromJS, "F")
    static callbackBeforeCollect := CallbackCreate((rfn, pfn) => ObjRelease(pfn), "F")
    rfn := JsRT.JsCreateFunction(callbackFromJS, pfn := ObjPtrAddRef(fn))
    JsRT.JsSetObjectBeforeCollectCallback(rfn, pfn, callbackBeforeCollect)
    return JsRT.FromJs(rfn)
}


CallFromJS(callee, isCtor, argv, argc, state) {
    argc &= 0xffff, isCtor &= 0xff ; Ignore possible garbage due to types smaller than pointer.
    try {
        fn := ObjFromPtrAddRef(state)
        if isCtor
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
    argc &= 0xffff, isCtor &= 0xff ; Ignore possible garbage due to types smaller than pointer.
    try {
        this := NumGet(argv, "ptr"), cls := ObjFromPtrAddRef(state)
        if !isCtor
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


; This ensures correct conversion of parameters and thrown exceptions
; (which would otherwise mostly come out as error 0x80020101).
CallIntoJS(callee, args) {
    return JsRT.FromJs(JsRT.JsCallFunction(callee, ArrayToArgv(args), args.Length))
}


ArrayToArgv(args) {
    b := BufferAlloc(args.Length * A_PtrSize, 0)
    for arg in args {
        if IsSet(&arg)
            NumPut 'ptr', ToJs(arg), b, (A_Index-1)*A_PtrSize
        else
            NumPut 'ptr', JsRT.JsGetUndefinedValue(), b, (A_Index-1)*A_PtrSize
    }
    return b
}


WrapClass(acls) {
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


WrapErrorClass(acls) {
    jcls := JsRT.Eval(Format('{ class {1} extends Error {}; {1}.prototype.name = "{1}"; {1} }', acls.Prototype.__class))
    acls.Prototype.__js := jcls.prototype
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
                p := AdjustMethodName(p)
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
            p := AdjustMethodName(p)
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
            case 10: ; JsArrayBuffer
                v := JsArrayBufferProxy(v)
            case 11: ; JsTypedArray
                v := JsTypedArrayProxy(v)
            case 12: ; JsDataView
                v := JsDataViewProxy(v)
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
    if v is Integer && (v < MIN_SAFE_INTEGER || v > MAX_SAFE_INTEGER)
        v := String(v)
    return JsRT.ToJs(v)
}


ErrorToJs(e) {
    if not e is Error
        return JsRT.ToJs(e)
    D e.message '`n' e.stack
    if e is TypeError
        return JsRT.ToJS(js.TypeError(StrReplace(e.message, "a ComO", "an o")))
    if e is MemberError && RegExMatch(e.message, 'named "(.*?)"', &m)
        return JsRT.ToJS(js.TypeError("Object doesn't support property or method '" m.1 "'"))
    je := js.Error(e.message)
    je.extra := e.Extra
    if (b := ObjGetBase(e)).HasProp('__js')
        je.__proto__ := b.__js
    return JsRT.ToJs(je)
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


class JsCachingProxy {
    static Call(rj) {
        if p := ExternalProperty(rj, '__p')
            return ObjFromPtrAddRef(p)
        return super(rj)
    }
    __New(rj) {
        this.__rj := rj
        JsRT.JsAddRef(rj)
        ; If a function is passed to SetTimer, OnMessage, etc. twice, it needs to
        ; be the same proxy object both times.  Built-in COM support would just
        ; create a new ComObject wrapper, which wouldn't allow an existing timer
        ; or callback to be deleted/unregistered.
        ; The naive approach is to create a ComObject once and store it in the JS
        ; object; but that creates a circular reference and prevents the objects
        ; from ever being deleted.  Instead, store an uncounted reference.
        ExternalProperty(rj, '__p', ObjPtr(this))
    }
    __Delete() {
        if err := JsRT.JsHasException()  ; Various Js APIs fail if in exception state, which seems to be not unusual when __delete is called.
            err := JsRT.JsGetAndClearException(), JsRT.JsAddRef(err)
        ; If the proxy is deleted, that means the program hasn't kept a reference
        ; to it, so it's okay for any future calls to pass a new proxy object.
        ; __p must be cleared because the JS object might be passed back to us.
        ExternalProperty(this.__rj, '__p', 0)
        JsRT.JsRelease(this.__rj)
        if err
            JsRT.JsSetException(err), JsRT.JsRelease(err)
    }
}


class JsFunctionProxy extends JsCachingProxy {
    Call(params*) {
        static missing := (_ => (_.Length := 1, _))([])
        params.InsertAt(1, missing*)
        return CallIntoJS(this.__rj, params)
    }
    MinParams => 0
    MaxParams => 0
    IsVariadic => true
}


class JsBufferProxy {
    __new(rj) => JsRT.JsAddRef(this.__rj := rj)
    __delete() => JsRT.JsRelease(this.__rj)
    Ptr => (this._GetStorage(&ptr), ptr)
    Size => (this._GetStorage(, &size), size)
}

class JsArrayBufferProxy extends JsBufferProxy {
    _GetStorage(&ptr:=unset, &length:=unset) {
        JsRT.JsGetArrayBufferStorage(this.__rj, &ptr:=0, &length:=0)
    }
}

class JsTypedArrayProxy extends JsBufferProxy {
    _GetStorage(&ptr:=unset, &length:=unset) {
        JsRT.JsGetTypedArrayStorage(this.__rj, &ptr:=0, &length:=0, 0, 0)
    }
}

class JsDataViewProxy extends JsBufferProxy {
    _GetStorage(&ptr:=unset, &length:=unset) {
        JsRT.JsGetDataViewStorage(this.__rj, &ptr:=0, &length:=0)
    }
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


PatchMenus() {
    hmenu := DllCall("GetMenu", "ptr", A_ScriptHwnd)
    DllCall("RemoveMenu", "ptr", hmenu, "uint", 65406, "uint", 0)
    DllCall("RemoveMenu", "ptr", hmenu, "uint", 65407, "uint", 0)
    
    A_TrayMenu.Delete
    global J_TrayMenu := Menu()
    global Menu_AddStandard := Menu.Prototype.AddStandard
    Menu.Prototype.DefineProp 'AddStandard', {Call: Menu_AddStandard_Fix}
    Menu_AddStandard_Fix J_TrayMenu
    
    MsgCommand(wParam, lParam, nmsg, hwnd) {
        switch wParam & 0xFFFF {
            case 65406: (A_IsCompiled) || ListLines() ; Allow for debug when not compiled.
            case 65407: (A_IsCompiled) || ListVars()
            case 65400, 65303: Reload
            case 65401, 65304: Edit
            case 65403, 65306: Pause -1
            case 65300: ; Open
                WinShow A_ScriptHwnd
                WinActivate A_ScriptHwnd
            default: return ; Allow all others
        }
        return 0
    }
    
    MsgNotifyIcon(wParam, lParam, nmsg, hwnd) {
        activate_default_tray_item() {
            global J_TrayMenu
            if -1 != default_id := DllCall("GetMenuDefaultItem", "ptr", J_TrayMenu.handle, "uint", false, "uint", 1)
                PostMessage(0x111, default_id,, A_ScriptHwnd)
        }
        switch lParam {
            case 0x205: ; WM_RBUTTONUP
                TrayMenu_Show_Fix J_TrayMenu, true
            case 0x201: ; WM_LBUTTONDOWN
                if J_TrayMenu.ClickCount = 1
                    activate_default_tray_item
            case 0x203: ; WM_LBUTTONDBLCLK
                activate_default_tray_item
        }
        return 0
    }
    
    ; OnMessage 0x111, MsgCommand
    ; OnMessage 1028, MsgNotifyIcon
    static newproc := CallbackCreate(WindowProc, "", 4) ; Not using "Fast" due to issues with tray menu & A_IsPaused.
    static oldproc := DllCall((A_PtrSize=8 ? "SetWindowLongPtrW" : "SetWindowLongW"), "ptr", A_ScriptHwnd, "int", -4, "ptr", newproc, "ptr")
    WindowProc(hwnd, nmsg, wParam, lParam) {
        if (nmsg = 0x111 && (wParam & 0xFFFF) >= 65300) {
            if "" != r := MsgCommand(wParam, lParam, nmsg, hwnd)
                return r
        }
        else if (nmsg = 1028) ; AHK_NOTIFYICON
            return MsgNotifyIcon(wParam, lParam, nmsg, hwnd)
        ; Mark this thread as immediately interruptible in case this message is one that should launch a new thread.
        Critical 0 ; Without this, hotkey, menu and clipboard threads cannot launch while a dialog is being displayed.
        return DllCall("CallWindowProc", "ptr", oldproc, "ptr", hwnd, "uint", nmsg, "ptr", wParam, "ptr", lParam, "ptr")
    }
}


Edit() {
    for hwnd in WinGetList(J_ScriptName) {
        if WinGetClass(hwnd) ~= '^(#32770|AutoHotkey)$'
            continue
        return WinActivate(hwnd)
    }
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
    dhw := A_DetectHiddenWindows
    switch StrLower(mode) {
        case 'force':
            TerminatePreviousInstance 'SingleInstance'
        case 'ignore':
            A_DetectHiddenWindows := true
            for hwnd in WinGetList(jktitle " ahk_class AutoHotkey")
                if hwnd != A_ScriptHwnd
                    ExitApp
        case 'prompt':
            prompted := false
            A_DetectHiddenWindows := true
            for hwnd in WinGetList(jktitle " ahk_class AutoHotkey") {
                if hwnd != A_ScriptHwnd {
                    if prompted || MsgBox("An older instance of this script is already running.  Replace it with this instance?",, "y/n") = "no"
                        ExitApp
                    prompted := true
                    TerminateInstance hwnd, 'SingleInstance'
                }
            }
        default:
            throw ValueError('Invalid mode "' mode '"')
    }
    A_DetectHiddenWindows := dhw
}


Include(path) {
    if !allow_wildcard_in_include && path ~= '[*?<>"]'  ; <>" are undocumented wildcard characters.
        throw Error('Include file "' path '" cannot be opened.')
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
    if allow_wildcard_in_include
        return included
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


_LoopFiles(pattern, mode, body:=unset) {
    IsSet(&body) || (body := mode, mode := 'F')
    static fields := ['attrib', 'dir', 'ext', 'fullPath', 'name', 'path', 'shortName'
        , 'shortPath', 'size', 'timeAccessed', 'timeCreated', 'timeModified']
    Loop Files pattern, mode {
        item := js.Object()
        for field in fields
            item.%field% := A_LoopFile%field%
        body(item)
    }
}


_LoopReg(keyname, mode, body:=unset) {
    IsSet(&body) || (body := mode, mode := 'F')
    static fields := ['name', 'type', 'key', 'timeModified']
    Loop Reg keyname, mode {
        item := js.Object()
        for field in fields
            item.%field% := A_LoopReg%field%
        body(item)
    }
}


AddHotkeySettings(scope) {
    hk := scope.hotkey, defProp := js.Object.defineProperty
    _Hotkey.B := '', _Hotkey.T := '', _Hotkey.I := '', _Hotkey.useHook := false
    defProp hk, AdjustPropName('MaxThreadsBuffer'), {
        get: ()      => _Hotkey.B ? jsTrue : jsFalse,
        set: (value) => _Hotkey.B := value ? 'B' : ''
    }
    defProp hk, AdjustPropName('MaxThreadsPerHotkey'), {
        get: ()      => _Hotkey.T ? Integer(SubStr(_Hotkey.T, 2)) : 1,
        set: (value) => _Hotkey.T := (value := intInRange(value, 1, 255)) != 1 ? 'T' value : ''
    }
    defProp hk, AdjustPropName('InputLevel'), {
        get: ()      => _Hotkey.I ? Integer(SubStr(_Hotkey.I, 2)) : 0,
        set: (value) => _Hotkey.I := (value := intInRange(value, 0, 100)) ? 'I' value : ''
    }
    defProp hk, AdjustPropName('UseHook'), {
        get: ()      => _Hotkey.useHook ? jsTrue : jsFalse,
        set: (value) => _Hotkey.useHook := value ? true : false
    }
    intInRange(i, low, high) {
        if (i := Integer(i)) < low || i > high
            throw ValueError("Invalid value")
        return i
    }
}

_Hotkey(keyname, callback:="", options:="") {
    try
        Hotkey keyname
    catch e {
        if not e is TargetError
            throw e
        ; This is a new hotkey, so insert the default options.
        options := _Hotkey.B  _Hotkey.T  _Hotkey.I  options
        ; Create the hotkey (this will throw if callback = On/Off/Toggle).
        Hotkey keyname, callback, options
        ; If useHook, apply $ after creating the hotkey so its "name" is not affected.
        if _Hotkey.useHook
            Hotkey '$' keyname
        return
    }
    ; Above didn't throw, so the hotkey already exists.
    if (callback != "" || options != "")
        Hotkey keyname, callback, options
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


Menu_AddStandard_Fix(m) {
    item_count() => DllCall('GetMenuItemCount', 'ptr', m.handle)
    id_exists(id) => DllCall('GetMenuState', 'ptr', m.handle, 'uint', id, 'uint', 0) != -1
    name_exists(name) {
        try {
            m.Rename name, name
            return true
        }
        return false
    }
    /* ; This is disabled for consistency and to facilitate testing.
    if !A_IsCompiled {
        ; Don't need as much complication.
        adding_open := !id_exists(65300)
        Menu_AddStandard(m)
        if !m.Default && adding_open && m = J_TrayMenu
            m.Default := "&Open"
        return
    }*/
    CMD(id) => (*) => PostMessage(0x111, id, 0, A_ScriptHwnd)
    static group := [
        [["&Open", CMD(65300)],
         ["&Help", CMD(65301)]],
        [["&Window Spy", CMD(65302)],
         ["&Reload This Script", CMD(65303)],
         ["&Edit This Script", CMD(65304)]],
        [["&Suspend Hotkeys", CMD(65305)],
         ["&Pause Script", CMD(65306)],
         ["E&xit", CMD(65307)]]
    ]
    ; Determine what's about to be added based on what exists.
    ; Normally the standard items have unique IDs, and those are used to determine
    ; whether to add each item.  That means a renamed standard item will still appear
    ; standard, while changing the callback changes the ID and therefore marks it as
    ; custom.  One drawback of that approach is that customizing an action and then
    ; calling AddStandard will add back the standard item with the same text.
    ; Another reason we don't try to use/preserve the standard IDs here is that it
    ; would be possible only for some of the items when this script is compiled,
    ; which complicates things and creates inconsistency.
    number_to_add(items) {
        n := 0
        for item in items
            if !name_exists(item[1])
                ++n
        return n
    }
    index := item_count() + 1
    adding1 := number_to_add(group[1]) > 1
    adding2 := number_to_add(group[2]) > 1
    adding3 := number_to_add(group[3]) > 1
    ; Determine whether to add separators based on which items are being added.
    ; Normally the standard separators have unique IDs, and are added only if not
    ; already present in the menu.  This doesn't try to replicate that exactly,
    ; but instead tries to separate the groups as they are normally.
    add_sep := [adding1 && (adding2 || adding3), adding2 && adding3, false]
    first_added := ""
    add_if_needed(name, action) {
        if !name_exists(name) {
            m.Add name, action
            if first_added = ""
                first_added := name
        }
    }
    ; Add the items.
    for items in group {
        for item in items
            if !name_exists(item[1])
                add_if_needed(item*)
        if add_sep[A_Index]
            m.Add
    }
    if m = J_TrayMenu && !m.Default && first_added = "&Open"
        m.Default := index '&'
}


TrayMenu_Show_Fix(m, postCmd:=false) { ; Fixes pause check mark (broken by window subclassing).
    if m = J_TrayMenu {
        try m.%A_IsPaused?"Check":"Uncheck"%("&Pause Script")
        try m.%A_IsSuspended?"Check":"Uncheck"%("&Suspend Hotkeys")
    }
    DllCall("GetCursorPos", "ptr", pt := BufferAlloc(8))
    x := NumGet(pt, 0, "int"), y := NumGet(pt, 4, "int")
    ; TPM_NONOTIFY := 0x80, TPM_RETURNCMD := 0x100, flags := TPM_NONOTIFY | TPM_RETURNCMD
    flags := postCmd ? 0x180 : 0
    GFW() => DllCall("GetForegroundWindow", "ptr")
    active_wnd := GFW()
    WinActivate A_ScriptHwnd
    id := DllCall("TrackPopupMenuEx", "ptr", m.handle, "uint", flags, "int", x, "int", y, "ptr", A_ScriptHwnd, "ptr", 0)
    if GFW() = A_ScriptHwnd
        WinActivate active_wnd
    if postCmd && id
        PostMessage 0x111, id,, A_ScriptHwnd
    ; return (Menu.Prototype.Show)(m)
}
