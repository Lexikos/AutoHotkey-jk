# AutoHotkey-jk

Aims to be a complete replacement for AutoHotkey.exe (when compiled), utilizing JavaScript instead of AutoHotkey's own language.

Requirements:
  - AutoHotkey v2.0-beta.6+
  - Windows 10+

## Compiling

Compilation is optional, but recommended when not debugging jk itself, as it makes the program behave a little more like the real AutoHotkey.

The following are expected to exist relative to the script's directory:
  - `bin32\AutoHotkey.exe`: Used with Ahk2Exe below.
  - `bin32\AutoHotkeySC.bin`: Provides the base binary for `AutoHotkey32.exe`.
  - `bin64\AutoHotkeySC.bin`: Provides the base binary for `AutoHotkey64.exe`.

If the binaries come from an AutoHotkey v2 zip download, they must be renamed appropriately. It is set up this way because `bin32` and `bin64` on the author's system are symbolic links to the output directories used to build AutoHotkey v2, in order to compile the script from cutting-edge builds rather than an official release.

A command line like the following may be used to compile the script:
```
Ahk2Exe.exe /ahk bin64\AutoHotkey.exe /in jk.ahk
```

If the Ahk2Exe GUI is used, the AutoHotkey executable Ahk2Exe uses must be for v2 alpha as indicated in the requirements above. Using the `/ahk` switch allows the use of the standard Ahk2Exe included with AutoHotkey v1.1.

## Running Scripts

### Uncompiled

If .ahk files are registered to run a supported version of AutoHotkey v2, it is sufficient to double-click jk.ahk or drag-drop a JavaScript file onto it.

Otherwise, jk.ahk must be passed to the correct AutoHotkey executable somehow. There are several ways to do this, but the most general way is to specify both paths on the command line, which allows any command line parameters to be appended. For example (full paths may be required):
```
AutoHotkeyU32.exe jk.ahk
```

### Compiled

When compiled, it is sufficient to double-click on the executable file or drag-drop a JavaScript file onto it.

[AutoHotkey32.jk](AutoHotkey32.jk) can be used to register the .jk filename extension (or an extension of your choice after editing it into the script) for the current user. Once registered, double-clicking a .jk file will execute it. Either run AutoHotkey32.exe or drag-drop AutoHotkey32.jk onto AutoHotkey64.exe, depending on which one you want to associate script files with. Run the script again to deregister the .jk extension.


### Parameters

The following standard parameters are recognized: `/restart`, `/cp` (with number suffix), `/ErrorStdOut` (with optional `=` value), `/Debug` (with optional `=` value).

When the script is compiled, or if any of these *precede* the `jk.ahk` parameter, they are also recognized by the real AutoHotkey. However, due to the way jk is designed, only `/Debug` should have an effect (and that one is ignored by jk).

The following standard parameters are **not** recognized: `/force`, `/validate`, `/iLib`.

The first unrecognized parameter is assumed to be the path of a JavaScript file. Any subsequent parameters are included in `A_Args`.

### Default Script File

If no unrecognized command line parameters are present, jk looks for `default_script_name` in the jk directory and in `A_MyDocuments`, in that order.
  - When compiled, `default_script_name` is defined as the base name of the executable file plus the `.j?` extension. A wildcard is used to match either `.jk` or `.js` (but could match other extensions if present). For example, `AutoHotkey32.jk`.
  - When not compiled, `default_script_name` is defined as `test.jk`.

If no file was found, a file selection dialog is shown. Canceling this will simply exit jk.

## Writing Scripts

Scripts are plain JavaScript code in a text file. AutoHotkey functionality is accessed through functions, built-in variables (properties of the global object) and classes.

Function and method names are imported in lower camel case, while class names and built-in variables are in upper camel case (or "PascalCase"). Built-in variables keep their `A_` prefix.

### Functions

Most standard AutoHotkey functions are available, unless they are redundant (like the Math functions), AutoHotkey-specific (like HasMethod or VarSetStrCapacity) or disabled because they do not work (Exit) or are potentially unsafe due to the way jk works (StrPtr). If in doubt, check the list of functions in [funcs.ahk](funcs.ahk). Disabled functions are prefixed with `!`.

Because JavaScript has no language feature equivalent to ByRef, the following functions return an object with a property for each output parameter (which should be omitted from the parameter list when calling the function):
  - caretGetPos: `{x, y}` -> false if no caret
  - controlGetPos: `{x, y, width, height}`
  - fileGetShortcut: `{target, dir, args, description, icon, iconNum, runState}`
  - imageSearch: `{x, y}` -> false if not found
  - loadPicture: `{imageType, handle}`
  - monitorGet, monitorGetWorkArea: `{left, top, right, bottom}`
  - mouseGetPos: `{x, y, win, control}`
  - pixelSearch: `{x, y}` -> false if not found
  - runWait: `{pid, exitCode}` (but run returns pid directly)
  - splitPath: `{name, dir, ext, nameNoExt, drive}`
  - winGetClientPos, winGetPos: `{x, y, width, height}`
  - Gui.prototype.getPos, Gui.prototype.getClientPos, Gui.Control.prototype.getPos: `{x, y, width, height}`

dllCall and comCall are available and mostly unchanged, but may be unsafe with regard to pointers on x64, as JavaScript does not support the full 64-bit integer range. Parameters with the `*` or `P` type suffix currently cannot produce output since the script has no way to create a VarRef, but ptr parameters can be used instead (e.g. with a single-element typed array such as `new Uint32Array(1)`).

### Variables

All built-in variables should be available except for the following: `A_IsCritical`, `A_Index`, `A_Loop`..., `A_Space`, `A_Tab`, `A_ThisFunc`

`A_HotkeyInterval`, `A_MaxHotkeysPerInterval` and `A_HotkeyModifierTimeout` are fully supported with v2.0-a130. For prior versions, they are given the usual default values (2000, 70, 50), but cannot be set.

### Classes

These classes are available: `ClipboardAll`, `File`, `Gui`, `InputHook`, `Menu`, `MenuBar`. Classes must be instantiated the normal JavaScript way; by using the `new` keyword.

Instead of a `Buffer`, use a JavaScript `ArrayBuffer`, typed array or `DataView`.

### Loops

Loop Parse has no replacement; JavaScript has enough ways to parse strings. Loop Files and Loop Reg are replaced with functions which accept a callback. Ideally they would be replaced with functions which return an iterator (to use with `for (x of y)`), but the nature of their implementation makes that difficult.

```
loopFiles(pattern, mode, callback);
loopFiles(pattern, callback);
```
`callback(file)` is called for each file. file has the following properties: attrib, dir, ext, fullPath, name, path, shortName, shortPath, size, timeAccessed, timeCreated, timeModified

```
loopReg(keyName, mode, callback);
loopReg(keyName, callback);
```
`callback(regItem)` is called for each key or value. regItem has the following properties: name, type, key, timeModified

### Directives

Supported directives are translated to either a function or a property. Some are not relevant, not implemented, or already had equivalent functions in AutoHotkey. The rest are described below.

```
include(path);
```
Evaluates the file in global scope, at run time. There is no `*i` option, but try-catch can be used, and it can be called conditionally, like any other function. As with #Include, it has no effect if called a second time for the same path (which is resolved to a full path and case corrected internally).

```
installKeybdHook();
installMouseHook();
persistent(persist);
```
Direct replacements for the corresponding directives prior to v2.0-a130 (which replaces the directives with functions). The `persist` parameter is supported prior to v2.0-a130, while `installKeybdHook` and `installMouseHook` support parameters only with v2.0-a130.

```
singleInstance(mode);
```
Scripts are not single-instance by default, as the script needs to run in order to override default behaviour. `singleInstance(mode)` accepts the case-insensitive mode strings 'force' (the default if omitted), 'ignore' and 'prompt'.

```
hotkey.inputLevel
hotkey.maxThreadsBuffer
hotkey.maxThreadsPerHotkey
hotkey.useHook
hotkey.suspendExempt
```
These properties directly replace the corresponding directives; of course, being properties and not directives, their values can be retrieved or changed at runtime. As before, these settings only affect the default options for newly created hotkey variants.  `suspendExempt` requires AutoHotkey v2.0-a130, and has no effect on earlier versions.

```
A_IconHidden = false;
```
Use this in place of #NoTrayIcon. The icon is not shown if this is used within 100ms of starting the script.

### Other Additions

```
collectGarbage();
```
Invokes a full garbage collection cycle. This is generally not necessary.

## Known Issues

jk uses the Edge JavaScript Runtime, which implies a few limitations:
  - It requires Windows 10.
  - Attempting to load the older engine used by IE11 (such as with a WebBrowser ActiveX control) may fail and cause the program to become unstable. Microsoft states that an app can support only one version of JsRT per process.
  - ES6 modules are not supported.

These limitations might be lifted by implementing [ChakraCore](https://github.com/chakra-core/ChakraCore), which is self-contained and separate from the engines included with the system. However:
  - ChakraCore.dll is currently around 7MB.
  - As ChakraCore is cross-platform, it does not natively support IDispatch or conversion of values to/from COM Variant, which jk currently relies on.