# Сборка и запуск Android Agent

## Целевая совместимость

Планшет использует ARMv7, Android API 19 и ядро Linux 3.4.67. В `agent.c` используется старый, совместимый интерфейс uinput:

- структура `struct uinput_user_dev` записывается в `/dev/uinput`;
- возможности задаются через `UI_SET_EVBIT`, `UI_SET_RELBIT` и `UI_SET_KEYBIT`;
- устройство создаётся и удаляется через `UI_DEV_CREATE` и `UI_DEV_DESTROY`.

Более новый `UI_DEV_SETUP` намеренно не применяется: он может отсутствовать в ядре 3.4.

## Сборка в Windows

Android NDK r25c установлен локально в `C:\Users\ants\AppData\Local\Android\Sdk
dk\25.2.9519653`. Выполните из корня проекта в PowerShell:

```powershell
$ndk = "$env:LOCALAPPDATA\Android\Sdk
dk\25.2.9519653"
& "$ndk\toolchains\llvm\prebuilt\windows-x86_64\bin\armv7a-linux-androideabi19-clang.cmd" `
  -Wall -Wextra -Werror -O2 -fPIE -pie -pthread `
  .\Android\agent.c -o .\Android\wifi_android_kvm_uinput_test
```

`armv7a-linux-androideabi19-clang` создаёт 32-битный ARMv7 ELF-файл, совместимый с Android 4.4.2 / API 19. Флаги `-fPIE -pie` требуются современными конфигурациями Android и не мешают API 19.

Агент ограничивает TCP-аутентификацию пятью секундами: подключение без AUTH не удерживает сервер. После AUTH включён TCP keepalive ядра (простой 5 секунд, три проверки через 2 секунды), поэтому пропавший Wi-Fi-клиент освобождает единственный слот без необходимости ждать системный TCP-таймаут.

## Копирование и запуск

Ниже намеренно указан серийный адрес Wi-Fi ADB: одновременно подключён и USB-транспорт, поэтому команды без `-s` будут неоднозначными.

```powershell
adb -s 172.16.0.222:5555 push .\Android\wifi_android_kvm_uinput_test /data/local/tmp/
adb -s 172.16.0.222:5555 shell "chmod 755 /data/local/tmp/wifi_android_kvm_uinput_test"
adb -s 172.16.0.222:5555 shell "su -c '/data/local/tmp/wifi_android_kvm_uinput_test --hold 20'"
```

Ожидаемый результат: после запуска на экране появляется системный курсор, через две секунды перемещается вправо, ещё через две секунды — вниз, затем возвращается в исходную область. Устройство остаётся доступно 20 секунд и затем удаляется.

Для остановки до тайм-аута используйте `Ctrl+C` в окне ADB. Программа обработает `SIGINT`, удалит виртуальное устройство и завершится.

## Диагностика

Проверьте, что ADB видит устройство и root имеет доступ:

```powershell
adb devices -l
adb -s 172.16.0.222:5555 shell "su -c 'id; ls -l /dev/uinput'"
```

Если программа сообщает `UI_DEV_CREATE: Invalid argument`, сохраните полный вывод этой команды и результат:

```powershell
adb -s 172.16.0.222:5555 shell "su -c 'cat /proc/bus/input/devices; dmesg | tail -n 80'"
```

Не продолжайте к TCP-агенту, пока не подтверждены создание устройства и движение курсора на самом планшете.

## Этап 2: запуск TCP-агента

Соберите тот же `agent.c`, скопируйте бинарник на планшет и запустите агент в первой консоли PowerShell:

```powershell
adb -s 172.16.0.222:5555 push .\Android\wifi_android_kvm_agent /data/local/tmp/
adb -s 172.16.0.222:5555 shell "su -c 'chmod 755 /data/local/tmp/wifi_android_kvm_agent; /data/local/tmp/wifi_android_kvm_agent --server'"
```

Во второй консоли создайте защищённый ADB-туннель:

```powershell
adb -s 172.16.0.222:5555 forward tcp:5556 tcp:5556
```

Агент слушает TCP на `0.0.0.0:5556` и discovery на `5557/UDP`. Windows-клиент подключается напрямую по Wi-Fi; ADB нужен только для установки и диагностики. Форматы описаны в [../docs/protocol.md](../docs/protocol.md). Для проверки нестандартного порта параметры можно сочетать в любом порядке:

```powershell
adb -s 172.16.0.222:5555 shell "su -c '/data/local/tmp/wifi_android_kvm_agent --server --port 6000 --right-button-back'"
```

Discovery в ответе укажет фактический TCP-порт `6000`.

Для остановки агента нажмите `Ctrl+C` в первой консоли. Агент освобождает все кнопки и удаляет виртуальную мышь.

### APK-приложение Android

Для обычного использования вместо ручного запуска установите [../AndroidApp/WiFiAndroidKVM.apk](../AndroidApp/WiFiAndroidKVM.apk):

```powershell
adb -s 172.16.0.222:5555 install -r .\AndroidApp\WiFiAndroidKVM.apk
```

В приложении одна кнопка: **«Запустить агент»** или **«Остановить агент»**. Перед запуском проверяются Android API, ARMv7, разрешение `su` и доступ root к `/dev/uinput`. При работе агент показан постоянным уведомлением foreground-службы; после выхода с экрана приложения сервис продолжает работать. Агент слушает TCP `0.0.0.0:5556` и отвечает на discovery `5557/UDP`; ADB-туннель не используется для рабочего соединения. APK не фиксирует портретную ориентацию, поэтому экран остаётся в текущем режиме Android. APK всегда запускает стандартный `BTN_RIGHT`, поэтому подходит для Xtralogic RDP.

Исходники APK находятся в `AndroidApp`; сборка выполняется из корня проекта:

```powershell
.\AndroidApp\build.ps1
```

Скрипт использует установленный Android SDK build-tools 36.1.0, Java и встраивает ARMv7-бинарник `AndroidApp/res/raw/wifi_android_kvm_agent`.

### Правая кнопка как Android Back

На этой прошивке домашний экран не различает обычные `BTN_RIGHT` и `BTN_LEFT`. Чтобы правая кнопка мыши выполняла системную команду Android Back, запускайте агент так:

```powershell
adb -s 172.16.0.222:5555 shell "su -c 'chmod 755 /data/local/tmp/wifi_android_kvm_agent; /data/local/tmp/wifi_android_kvm_agent --server --right-button-back'"
```

Этот режим добавляет `KEY_BACK` к виртуальному устройству и преобразует только пакет правой кнопки в нажатие и отпускание `KEY_BACK`. Левая и средняя кнопки, движение и колесо не меняются. Обычный запуск `--server` сохраняет исходное событие `BTN_RIGHT`. Не используйте `--right-button-back` вместе с Xtralogic RDP: RDP обрабатывает Back как команду разрыва сеанса.

### Клавиатура

В режиме `--server` агент также создаёт устройство `WiFiAndroidKVM keyboard`. Пакет `KEY` передаёт Linux input key code; при закрытии TCP или остановке агента все нажатые клавиши освобождаются. Полный формат пакета приведён в [../docs/protocol.md](../docs/protocol.md).

Агент принимает только коды, которые посылает Windows-клиент: основной набор до F12, клавиши дополнительной цифровой клавиатуры и навигации, правые Ctrl/Alt и клавиши Win. Системные кнопки питания, сна, пробуждения и `BTN_*` отбрасываются; виртуальное устройство объявляет только этот клавиатурный набор.

AUTH-ключ `KVM2026` — фиксированный общий секрет действующей версии и передаётся по TCP без шифрования. Используйте программу только в доверенной локальной сети. Переход на индивидуальный секрет и HMAC потребует согласованного изменения Windows-клиента и TCP-протокола.

На SurfPad 4M общий `Generic.kl` ошибочно сопоставляет часть обычных evdev-кодов с жестами. Поэтому клавиатура объявляется совместимой с уже установленным keylayout `Vendor_046d_Product_c532.kl`; этот файл правильно назначает Backspace, буквенные и навигационные клавиши.


