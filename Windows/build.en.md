# Building and using the Windows client

[Русская версия](build.md).

`WiFiAndroidKVM.pb` is UTF-8 with BOM. Build it with PureBasic 6.41 x64 and `/THREAD`:

```powershell
$buildDir = Join-Path $env:TEMP 'wifi_android_kvm_pb_build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Copy-Item .\Windows\WiFiAndroidKVM.pb (Join-Path $buildDir 'WiFiAndroidKVM.pb') -Force
Copy-Item .\Windows\WiFiAndroidKVM.ico (Join-Path $buildDir 'WiFiAndroidKVM.ico') -Force
& 'C:\Program Files\PureBasic\Compilers\pbcompiler.exe' `
  (Join-Path $buildDir 'WiFiAndroidKVM.pb') /THREAD /EXE (Join-Path $buildDir 'WiFiAndroidKVM.exe') /ICON (Join-Path $buildDir 'WiFiAndroidKVM.ico')
if ($LASTEXITCODE -ne 0) { throw 'PureBasic compilation failed' }
Copy-Item (Join-Path $buildDir 'WiFiAndroidKVM.exe') .\Windows\WiFiAndroidKVM.exe -Force
```

Place the UTF-8 `WiFiAndroidKVM.lng` beside the EXE. English is embedded and is always available. The file contains named language sections such as `[ru]`, `Name=Русский`, and `Key=Value` text entries. The client reads every section at startup and offers it in the window and a dedicated language submenu in the tray; empty or missing values use built-in English. The section code is saved in `WiFiAndroidKVM.ini`, and the file can contain any number of languages.

Use `/silent` or `/s` to launch into the tray. The **Start with Windows** checkbox writes the current-user Run value `WiFiAndroidKVM` with the full EXE path plus `/silent`; clearing it removes the value. No administrator rights are needed.

Start Android Agent first. The client discovers agents through UDP broadcast on port 5557. Select a discovered device, or enter IP/DNS and port 5556 manually. The first TCP packet is AUTH; TCP_NODELAY is enabled. A tray icon provides show/hide, enable/disable tablet control, language selection and Exit.

Press `Ctrl+Alt+M` to enable tablet control and again to restore Windows input. While remote control is enabled, the client confines the Windows cursor and shows a topmost capture reminder. The main Delete key and the Delete function of the numeric keypad are forwarded as Delete. Mouse sensitivity is 25–300%; 100% retains the original speed. KeepAlive can be enabled with a 10–1000 ms interval; 700 ms was confirmed by the user to work normally.

Manual connection runs in a worker thread, so an unavailable tablet does not block the window or global hooks. On disabling remote control, key-up for every held key is queued and sent before DISCONNECT. Unmapped keys, X buttons, and the horizontal wheel are not sent, and are also kept from reaching Windows while tablet control is active.

When returning with `Ctrl+Alt+M`, the client consumes the final Ctrl, Alt, and M key-up events because their key-down events were already captured. It also explicitly releases the Windows Shift, Ctrl, and Alt states, so Windows cannot retain a modifier after remote mode ends.
