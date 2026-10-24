# Mouse transport diagnostics

[Русская версия](mouse_diagnostics.md).

Use this check only when Raw Input and sent-movement counters increase but the tablet pointer still pauses or moves unevenly. It measures receipt timing without changing the Android virtual input configuration.

1. Start the Android Agent and connect the Windows client normally.
2. Keep the client in tablet-control mode and record the two counters shown in its window: **Raw Input** and **Packets sent**.
3. Move the mouse continuously for several seconds, then record both counters again.
4. Report whether the Windows pointer stayed fixed, whether the client window was active, whether buttons worked, the selected sensitivity, KeepAlive state and interval, and whether the Android pointer paused.

Raw Input counts nonzero physical relative movements. Packets sent counts the queued MOVE packets after client-side accumulation and `int16` packet splitting, so the two totals are not expected to match. Mouse sensitivity changes the Android movement amount; it does not alter mouse-button, wheel or keyboard packets.

The optional transport probe is built and used from the project root. It must use the device-specific ADB serial for every device command:

```powershell
adb -s 172.16.0.222:5555 shell "su -c 'ps | grep wifi_android_kvm'"
```

The probe is diagnostic only. It does not replace the authenticated TCP protocol and does not change the Agent, APK or input devices.
