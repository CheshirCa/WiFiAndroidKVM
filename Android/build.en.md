# Android Agent build and deployment

[Русская версия](build.md).

The target is PocketBook SURFpad 4M: ARMv7, Android 4.4.2 / API 19, Linux 3.4.67, root access and `/dev/uinput`. The source uses the older compatible `uinput_user_dev`, `UI_SET_*BIT`, `UI_DEV_CREATE` and `UI_DEV_DESTROY` interface rather than newer APIs.

Build from the project root with Android NDK r25c:

```powershell
$ndk = 'C:\Users\ants\AppData\Local\Android\Sdk\ndk\25.2.9519653'
& "$ndk\toolchains\llvm\prebuilt\windows-x86_64\bin\armv7a-linux-androideabi19-clang.cmd" `
  -Wall -Wextra -Werror -O2 -fPIE -pie -pthread `
  .\Android\agent.c -o .\Android\wifi_android_kvm_agent
```

Use the required Wi-Fi ADB serial for every device command:

```powershell
adb -s 172.16.0.222:5555 push .\Android\wifi_android_kvm_agent /data/local/tmp/
adb -s 172.16.0.222:5555 shell "su -c 'chmod 755 /data/local/tmp/wifi_android_kvm_agent; /data/local/tmp/wifi_android_kvm_agent --server'"
```

For normal use install `AndroidApp/WiFiAndroidKVM.apk` instead. Its foreground service deploys and runs the same agent. The agent listens on `0.0.0.0:5556`, requires AUTH with `KVM2026` as the first TCP packet, enables TCP_NODELAY and responds to UDP discovery on port 5557. It does not force portrait orientation.

Authentication has a five-second receive timeout, so a connection that never sends AUTH cannot occupy the server. After authentication, TCP keepalive uses a five-second idle period and three two-second probes to detect a vanished Wi-Fi client without changing application KeepAlive behavior. `--server --port 6000 --right-button-back` is valid in any option order; discovery advertises the selected TCP port.

The virtual keyboard declares USB ID `046d:c532` so SurfPad uses the correct installed keylayout. It declares and accepts only the keys emitted by the Windows client, rather than `KEY_MAX`; power, sleep, wake, and `BTN_*` codes are rejected.

`KVM2026` is a fixed shared secret sent unencrypted by the current protocol. Use the Agent only on a trusted LAN. Individual secrets and HMAC would require a coordinated Windows-client and protocol update.
