# WiFi Android KVM 0.4.6 — User Guide

Copyright: [Copyright (C) CheshirCa 2026](https://t.me/cheshircanest). The software is provided “as is”. Full non-commercial license terms are in `LICENSE`.

## Package contents

The `android` folder contains `WiFiAndroidKVM.apk` and the `windows` folder contains `WiFiAndroidKVM.exe` with its embedded application icon and `WiFiAndroidKVM.lng`. Source code is not included in the distribution.

## Android

Install the APK on a PocketBook SURFpad 4M running Android 4.4.2 / API 19. Open it and press **Start agent**. The application checks root and `/dev/uinput`, then Agent accepts Wi-Fi connections on TCP port 5556 and answers discovery on UDP port 5557. It does not lock screen orientation.

## Windows

Run `WiFiAndroidKVM.exe`. The client automatically searches the LAN for an Agent; double-click a discovered tablet or enter its IP/DNS and TCP port 5556 manually. To start with only a tray icon, use:

```text
WiFiAndroidKVM.exe /silent
```

`/s` is an equivalent switch.

At startup, the EXE reads `WiFiAndroidKVM.lng` beside the program and offers English plus every language section in the window and dedicated language submenu in the tray. English is built into the EXE. A section contains a code and name, for example `[ru]` and `Name=Русский`; text entries use `Key=Translation`. Empty or omitted translations use the built-in English text. Current settings and the selected language code are stored in `WiFiAndroidKVM.ini` beside the program.

The **Start with Windows** checkbox starts the client hidden after the current user signs in. It does not require administrator rights; clear the same checkbox to remove autostart.

## Controls

Press `Ctrl+Alt+M` to send mouse and keyboard control to the tablet. A persistent topmost capture reminder appears. Press `Ctrl+Alt+M` again to return control to Windows. The tray menu provides show/hide, enable/disable tablet control, language selection, and Exit. Closing the main window only hides it; choose **Exit** in the tray for a complete shutdown.

After returning with `Ctrl+Alt+M`, you can immediately continue using the Windows keyboard; the final releases of that shortcut are not passed to Windows separately, and the Shift, Ctrl, and Alt states are explicitly cleared.

Mouse sensitivity is adjustable from 25% to 300%; 100% is the original speed. KeepAlive and auto reconnect are available in the main window. The main Delete key and the Delete function of the numeric keypad are sent to the tablet as Delete. Cursor transition through a screen edge is not used.

The main window is organized into Devices, Connection, Control, and Mouse sensitivity sections. Mouse-event and movement-packet counters, along with the control state, appear at the bottom. If a manual connection is unavailable, the window remains responsive because connection runs in the background. When remote control is disabled, every held key is released on the tablet first. Use the application only on a trusted LAN: the current AUTH key is fixed and unencrypted.
