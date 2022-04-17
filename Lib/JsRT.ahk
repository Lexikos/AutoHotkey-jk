/*
 *  JsRT for AutoHotkey v2.0-a128
 *
 *  Utilizes the JavaScript engine that comes with IE11 or legacy Edge.
 *
 *  License: Use, modify and redistribute without limitation, but at your own risk.
 */
class JsRT
{
    static Call()
    {
        throw Error("This class is abstract. Use JsRT.IE() or JSRT.Edge() to initialize.", -1)
    }
    
    static IE()
    {
        if !this._hmod := DllCall("LoadLibrary", "str", "jscript9", "ptr")
            throw Error("Failed to load jscript9.dll", -1)
        if DllCall("jscript9\JsCreateRuntime", "int", 0, "int", -1, "ptr", 0, "ptr*", &runtime:=0) != 0
            throw Error("Failed to initialize JsRT", -1)
        ; The following API differs between jscript9 and chakra:
        DllCall("jscript9\JsCreateContext", "ptr", runtime, "ptr", 0, "ptr*", &context:=0)
        return this._Initialize("jscript9", runtime, context)
    }
    
    static Edge()
    {
        if !this._hmod := DllCall("LoadLibrary", "str", "chakra", "ptr")
            throw Error("Failed to load chakra.dll", -1)
        if DllCall("chakra\JsCreateRuntime", "int", 0, "ptr", 0, "ptr*", &runtime:=0) != 0
            throw Error("Failed to initialize JsRT", -1)
        ; The following API differs between jscript9 and chakra:
        DllCall("chakra\JsCreateContext", "ptr", runtime, "ptr*", &context:=0)
        return this._Initialize("chakra", runtime, context)
    }
    
    static _Initialize(dll, runtime, context)
    {
        this._dll := dll
        this._runtime := runtime
        this._context := context
        this._ImportAPI()
        DllCall(dll "\JsSetCurrentContext", "ptr", context)
        this._sources := Map()
        this._sources.CaseSense := 'Off'
        this._sources['eval'] := 0
        return this._dsp := this.FromJs(this.JsGetGlobalObject())
    }
    
    static _ImportAPI()
    {
        API := '
        (
            JsAddRef(ptr ref, uint* return count)
            JsBooleanToBool(ptr valref, char* return bool)
            JsCallFunction(ptr function, ptr arguments, ushort argumentCount, ptr* return valref)
            JsCollectGarbage(ptr runtime)
            JsCreateError(ptr message, ptr* return valref)
            JsCreateExternalObject(ptr data, ptr finalizeCallback, ptr* return valref)
            JsCreateFunction(ptr nativeGetCb, ptr callbackState, ptr* return valref)
            JsCreateTypeError(ptr message, ptr* return valref)
            JsGetAndClearException(ptr* return valref)
            JsGetArrayBufferStorage(ptr arrayBuffer, ptr* buf, int* byteCount)
            JsGetDataViewStorage(ptr dataView, ptr* buf, int* byteCount)
            JsGetExternalData(ptr object, ptr* return)
            JsGetGlobalObject(ptr* return valref)
            JsGetOwnPropertyNames(ptr object, ptr* return valref)
            JsGetOwnPropertySymbols(ptr object, ptr* return valref)
            JsGetProperty(ptr object, ptr propertyId, ptr* return valref)
            JsGetPropertyIdFromName(str name, ptr* return propId)
            JsGetPrototype(ptr object, ptr* return valref)
            JsGetTypedArrayStorage(ptr typedArray, ptr* buf, int* byteCount, int* arrayType, int* elemSize)
            JsGetUndefinedValue(ptr* return undefined)
            JsGetValueType(ptr value, int* return)
            JsHasException(char* return bool)
            JsHasExternalData(ptr object, char* return bool)
            JsIdle(uint* return nextIdleTick)
            JsInstanceOf(ptr object, ptr constructor, char* return bool)
            JsParseScript(wstr script, ptr sourceContext, wstr sourceUrl, ptr* return valref)
            JsPointerToString(ptr stringValue, uptr stringLength, ptr* return valref)
            JsProjectWinRTNamespace(wstr namespace)
            JsRelease(ptr ref, uint* return count)
            JsRunScript(wstr script, ptr sourceContext, wstr sourceUrl, ptr* return valref)
            JsSetException(ptr exception)
            JsSetExternalData(ptr object, ptr data)
            JsSetObjectBeforeCollectCallback(ptr ref, ptr callbackState, ptr callback)
            JsSetProperty(ptr object, ptr propertyId, ptr value, char useStrictRules)
            JsSetPrototype(ptr object, ptr proto)
            JsValueToVariant(ptr valref, ptr variant)
            JsVariantToValue(ptr variant, ptr* return valref)
        )'
        
        static kernel32 := DllCall("GetModuleHandle", "str", "kernel32", "ptr")
        static GPA := DllCall.Bind(DllCall("GetProcAddress", "ptr", kernel32, "astr", "GetProcAddress", "ptr"), "ptr", , "astr", , "ptr")
        
        Loop Parse API, '`n'
        {
            if !RegExMatch(A_LoopField, "^(\w+)\((.*)\)$", &m)
            {
                MsgBox "DEBUG: Fatal error in JsRT API declarations, line " A_Index
                ExitApp
            }
            funcname := m.1
            argtypes := RegExReplace(m.2, '(?<=^|,) *(\w+(?: *\*|[Pp](?= ))?) *+([\w ]*?) *(?=,|$)', '$1,$2')
            argtypes := StrSplit(argtypes, ',', ' ')
            
            if !(pfn := GPA(this._hmod, funcname))
                throw Error('Failed to load JsRT function "' funcname '" from DLL "' this._dll '"')
            api := {ptr: pfn, name: funcname}
            
            if argtypes.Length && argtypes[-1] ~= '^return\b'
                api.return := argtypes.Length
            Loop argtypes.Length // 2
                argtypes.Delete A_Index * 2
            
            this.%funcname% := (api.HasProp('return') ? CallApiRet : CallApi)
                                .Bind( , api, argtypes*)
        }
        
        CallApi(thisJsRT, api, args*)
        {
            if errorCode := DllCall(api.ptr, args*)
                this._ThrowApiError api.name, errorCode
        }
        
        CallApiRet(thisJsRT, api, args*)
        {
            args[api.return] := &(retval := 0)
            if errorCode := DllCall(api.ptr, args*)
                this._ThrowApiError api.name, errorCode
            return retval
        }
    }
    
    static _ThrowApiError(apiName, errorCode)
    {
        ; JsErrorScriptException || JsErrorScriptCompile
        if errorCode = 0x30001 || errorCode = 0x30002 ;|| errorCode = 0x10004
            throw this.FromJs(this.JsGetAndClearException())
        throw (this.Error)(Format("Call to {1} failed with error 0x{2:x}", apiName, errorCode), -1, errorCode)
    }
    
    static __Delete()
    {
        this._dsp := ""
        if dll := this._dll
        {
            DllCall(dll "\JsSetCurrentContext", "ptr", 0)
            DllCall(dll "\JsDisposeRuntime", "ptr", this._runtime)
        }
        DllCall("FreeLibrary", "ptr", this._hmod)
    }
    
    static FromJs(valref)
    {
        ref := ComValue(0x400C, (var := Buffer(24, 0)).ptr)
        this.JsValueToVariant(valref, var)
        return (val := ref[], ref[] := 0, val)
    }
    
    static ToJs(val)
    {
        ref := ComValue(0x400C, (var := Buffer(24, 0)).ptr)
        ref[] := val
        valref := this.JsVariantToValue(var)
        ref[] := 0
        return valref
    }
    
    static SourceContext(filename)
    {
        if !this._sources.has(filename)
            this._sources[filename] := this._sources.Count
        return this._sources[filename]
    }
    
    static RunFile(filename, readOpt:="")
    {
        ; Pass a unique sourceContext for each filename.  Passing the same sourceContext
        ; each time causes stack traces to show only the first sourceUrl ever passed.
        this.JsRunScript(FileRead(filename, readOpt), this.SourceContext(filename), filename)
    }
    
    static Eval(code)
    {
        return this.FromJs(this.JsRunScript(code, 0, "eval"))
    }
    
    class Error extends Error
    {
    }
}
