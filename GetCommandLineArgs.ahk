GetCommandLineArgs() {
    if !ptr := DllCall("shell32\CommandLineToArgvW", "ptr", DllCall("GetCommandLineW", "ptr"), "int*", &nargs:=0, "ptr")
        throw MemoryError()
    try {
        args := []
        loop nargs
            args.Push StrGet(NumGet(ptr, (A_Index-1)*A_PtrSize, "ptr"), "UTF-16")
        return args
    }
    finally DllCall("LocalFree", "ptr", ptr)
}