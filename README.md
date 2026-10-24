# WiFi Android KVM

![WiFi Android KVM](https://github.com/CheshirCa/WiFiAndroidKVM/blob/main/doc/screenshot.jpg)

**Version 0.4.6.** A compact Wi-Fi KVM that sends Windows mouse and keyboard input to a rooted Android tablet without transferring video. The tested device is a PocketBook SURFpad 4M running Android 4.4.2 / API 19, ARMv7, Linux 3.4.67.

## English

The Windows client is written in PureBasic and the Android Agent is native C. Press `Ctrl+Alt+M` to give the tablet control; press it again to return control to Windows. The client supports UDP discovery, manual IP/DNS and port entry, TCP authentication, optional KeepAlive, background reconnect checks, a tray icon, mouse sensitivity, silent startup, and per-user Windows autostart.

Android requires root access and `/dev/uinput`. The Agent listens on TCP 5556 and replies to discovery on UDP 5557. The current AUTH key is fixed and unencrypted, so use the software only on a trusted local network.

Start here:

- [Windows build instructions](Windows/build.en.md)
- [Android build instructions](Android/build.en.md)
- [User guide](docs/UserGuide.en.md)
- [Protocol](docs/protocol.en.md)
- [Mouse diagnostics](docs/mouse_diagnostics.en.md)
- [Change log](CHANGELOG.en.md)

This source repository intentionally excludes generated binaries, including the EXE, APK, native Agent executables, local INI settings, and signing outputs. The local `Release/` staging directory contains the prepared GitHub assets: `WiFiAndroidKVM-0.4.6-windows-x64.zip`, `WiFiAndroidKVM-0.4.6-android-armv7.apk`, and `SHA256SUMS.txt`.

## Русский

**Версия 0.4.6.** Компактный Wi-Fi KVM передаёт ввод мыши и клавиатуры Windows на Android-планшет без передачи изображения. Проверенная платформа — PocketBook SURFpad 4M с Android 4.4.2 / API 19, ARMv7 и Linux 3.4.67.

Клиент Windows написан на PureBasic, Android Agent — на C. `Ctrl+Alt+M` передаёт управление планшету, повторное нажатие возвращает его Windows. Клиент поддерживает UDP-поиск, ручной IP/DNS и порт, TCP-авторизацию, опциональный KeepAlive, фоновую проверку переподключения, системный трей, чувствительность мыши, тихий запуск и автозапуск текущего пользователя.

Для Android требуются root и `/dev/uinput`. Agent слушает TCP 5556 и отвечает на поиск UDP 5557. Текущий ключ AUTH фиксированный и не шифруется, поэтому используйте программу только в доверенной локальной сети.

Основные документы:

- [Сборка Windows](Windows/build.md)
- [Сборка Android](Android/build.md)
- [Руководство пользователя](docs/UserGuide.ru.md)
- [Протокол](docs/protocol.md)
- [Диагностика мыши](docs/mouse_diagnostics.md)
- [История изменений](CHANGELOG.md)

В этот набор намеренно не включены собранные EXE, APK, исполняемые файлы Agent, локальный INI и результаты подписи. Локальная папка `Release/` содержит подготовленные вложения GitHub Release: `WiFiAndroidKVM-0.4.6-windows-x64.zip`, `WiFiAndroidKVM-0.4.6-android-armv7.apk` и `SHA256SUMS.txt`.

## Source layout / Структура исходников

```text
Android/       Native ARMv7 Agent source and build instructions
AndroidApp/    Android APK wrapper source and build script
Windows/       PureBasic client source, icon, language file, build instructions
docs/          Bilingual user, protocol, and diagnostics documentation
```

Copyright (C) CheshirCa 2026 — [Telegram](https://t.me/cheshircanest). See [LICENSE](LICENSE) for the non-commercial license.
