; This lists all v2 functions at the time of writing (v2.0-a129).
; Functions with a non-word char prefix are disabled.
functions := "
(Join`s
!Abs !ACos !ASin !ATan BlockInput BufferAlloc CallbackCreate CallbackFree
CaretGetPos !Ceil !Chr Click ClipWait ComCall ComObjActive ComObjArray
ComObjConnect ComObjCreate ComObject ComObjFlags ComObjGet ComObjQuery
ComObjType ComObjValue ControlAddItem ControlChooseIndex ControlChooseString
ControlClick ControlDeleteItem ControlFindItem ControlFocus ControlGetChecked
ControlGetChoice ControlGetClassNN ControlGetEnabled ControlGetExStyle
ControlGetFocus ControlGetHwnd ControlGetIndex ControlGetItems ControlGetPos
ControlGetStyle ControlGetText ControlGetVisible ControlHide ControlHideDropDown
ControlMove ControlSend ControlSendText ControlSetChecked ControlSetEnabled
ControlSetExStyle ControlSetStyle ControlSetText ControlShow ControlShowDropDown
CoordMode !Cos !Critical !DateAdd !DateDiff DetectHiddenText DetectHiddenWindows
DirCopy DirCreate DirDelete DirExist DirMove DirSelect DllCall Download
DriveEject DriveGetCapacity DriveGetFilesystem DriveGetLabel DriveGetList
DriveGetSerial DriveGetSpaceFree DriveGetStatus DriveGetStatusCD DriveGetType
DriveLock DriveSetLabel DriveUnlock Edit EditGetCurrentCol EditGetCurrentLine
EditGetLine EditGetLineCount EditGetSelectedText EditPaste EnvGet EnvSet
!Exception !Exit ExitApp !Exp FileAppend FileCopy FileCreateShortcut FileDelete
FileEncoding FileExist FileGetAttrib FileGetShortcut FileGetSize FileGetTime
FileGetVersion FileInstall FileMove FileOpen FileRead FileRecycle
FileRecycleEmpty FileSelect FileSetAttrib FileSetTime !Floor Format FormatTime
GetKeyName GetKeySC GetKeyState GetKeyVK !GetMethod GroupActivate GroupAdd
GroupClose GroupDeactivate GuiCtrlFromHwnd GuiFromHwnd !HasBase !HasMethod !HasProp
HotIf HotIfWinActive HotIfWinExist HotIfWinNotActive HotIfWinNotExist Hotkey
Hotstring IL_Add IL_Create IL_Destroy ImageSearch IniDelete IniRead IniWrite
InputBox !InStr !IsAlnum !IsAlpha !IsDigit !IsFloat !IsInteger !IsLabel !IsLower
!IsNumber !IsObject !IsSet !IsSpace !IsTime !IsUpper !IsXDigit KeyHistory KeyWait
ListHotkeys !ListLines !ListVars ListViewGetContent !Ln LoadPicture !Log !LTrim !Max
MenuFromHandle MenuSelect !Min !Mod MonitorGet MonitorGetCount MonitorGetName
MonitorGetPrimary MonitorGetWorkArea MouseClick MouseClickDrag MouseGetPos
MouseMove MsgBox NumGet NumPut ObjAddRef !ObjBindMethod !ObjFromPtr
!ObjFromPtrAddRef !ObjGetBase !ObjGetCapacity !ObjHasOwnProp !ObjOwnPropCount
!ObjOwnProps !ObjPtr !ObjPtrAddRef !ObjRelease !ObjSetBase !ObjSetCapacity
OnClipboardChange OnError OnExit OnMessage !Ord OutputDebug Pause PixelGetColor
PixelSearch PostMessage ProcessClose ProcessExist ProcessSetPriority ProcessWait
ProcessWaitClose Random RandomSeed RegDelete RegDeleteKey !RegExMatch
!RegExReplace RegRead RegWrite Reload !Round !RTrim Run RunAs RunWait Send
SendEvent SendInput SendLevel SendMessage SendMode SendPlay SendText
SetCapslockState SetControlDelay SetDefaultMouseSpeed SetKeyDelay SetMouseDelay
SetNumlockState SetRegView SetScrollLockState SetStoreCapsLockMode SetTimer
SetTitleMatchMode SetWinDelay SetWorkingDir Shutdown !Sin Sleep !Sort SoundBeep
SoundGetInterface SoundGetMute SoundGetName SoundGetVolume SoundPlay
SoundSetMute SoundSetVolume SplitPath !Sqrt StatusBarGetText StatusBarWait
!StrCompare StrGet !StrLen !StrLower !StrPtr StrPut !StrReplace !StrSplit !StrUpper
!SubStr Suspend SysGet SysGetIPAddresses !Tan Thread ToolTip TraySetIcon TrayTip
!Trim !Type !VarSetStrCapacity WinActivate WinActivateBottom WinActive WinClose
WinExist WinGetClass WinGetClientPos WinGetControls WinGetControlsHwnd
WinGetCount WinGetExStyle WinGetID WinGetIDLast WinGetList WinGetMinMax
WinGetPID WinGetPos WinGetProcessName WinGetProcessPath WinGetStyle WinGetText
WinGetTitle WinGetTransColor WinGetTransparent WinHide WinKill WinMaximize
WinMinimize WinMinimizeAll WinMinimizeAllUndo WinMove WinMoveBottom WinMoveTop
WinRedraw WinRestore WinSetAlwaysOnTop WinSetEnabled WinSetExStyle WinSetRegion
WinSetStyle WinSetTitle WinSetTransColor WinSetTransparent WinShow WinWait
WinWaitActive WinWaitClose WinWaitNotActive
)"

; Functions which accept a callback need special handling to ensure the
; same object is passed each time.  The parameter number is 1-based.
callback_params := {
    CallbackCreate: 1,
    HotIf: 1,
    Hotkey: 2,
    OnClipboardChange: 1,
    OnError: 1,
    OnExit: 1,
    OnMessage: 2,
    SetTimer: 1,
}

; Output parameters are indicated by position in the array and given
; names suitable for properties of a returned object.
output_params := {
    CaretGetPos: ['x', 'y'],
    ControlGetPos: ['x', 'y', 'width', 'height'],
    FileGetShortcut: [, 'target', 'dir', 'args', 'description', 'icon', 'iconNum', 'runState'],
    ImageSearch: ['x', 'y'],
    LoadPicture: [, , 'imageType'],
    MonitorGet: [, 'left', 'top', 'right', 'bottom'],
    MonitorGetWorkArea: [, 'left', 'top', 'right', 'bottom'],
    MouseGetPos: ['x', 'y', 'win', 'control'],
    PixelSearch: ['x', 'y'],
    ; RegExMatch: [, , 3],
    ; RegExReplace: [, , , 4],
    Run: [, , , 'pid'],
    RunWait: [, , , 'pid'],
    SplitPath: [, 'name', 'dir', 'ext', 'nameNoExt', 'drive'],
    ; StrReplace: [, , , , 5],
    ; VarSetStrCapacity: [1],
    WinGetClientPos: ['x', 'y', 'width', 'height'],
    WinGetPos: ['x', 'y', 'width', 'height'],
}

; These callback functions act as an additional filter for functions
; listed in output_params.
; Param #1 (r): the original return value.
; Param #2 (o): an object with one property for each name from output_params.
; Should return: the final return value.
output_params_return := {
    CaretGetPos: (r, o) => (r ? o : ''),
    ImageSearch: (r, o) => (r ? o : ''),
    LoadPicture: (r, o) => (o.handle := r, o),
    PixelSearch: (r, o) => (r ? o : ''),
    Run: (r, o) => o.pid,
    RunWait: (r, o) => (o.exitCode := r, o),
}
