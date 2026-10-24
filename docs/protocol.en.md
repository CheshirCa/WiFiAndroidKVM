# WiFi Android KVM protocol

[Русская версия](protocol.md).

Android Agent listens on TCP `0.0.0.0:5556`. Every connection must begin with an 8-byte AUTH packet containing ASCII key `KVM2026`, completed within five seconds; any input before AUTH is rejected. TCP is a byte stream, so Agent accumulates bytes until a complete 8-byte packet is available. TCP_NODELAY is enabled at both ends. After AUTH, kernel TCP keepalive uses a five-second idle period and three two-second probes to release a vanished client slot.

All TCP packets are 8 bytes. Integers are little-endian; unused bytes are zero.

| Type | Name | Payload |
|---:|---|---|
| `0x01` | MOVE | bytes 1–2: `int16 dx`; bytes 3–4: `int16 dy` |
| `0x02` | BUTTON | byte 1: 1 left, 2 right, 3 middle; byte 2: 0 release, 1 press |
| `0x03` | WHEEL | bytes 1–2: `int16 delta`; positive scrolls up |
| `0x04` | KEY | bytes 1–2: `uint16` Linux input key code; byte 3: 0 release, 1 press |
| `0x7d` | AUTH | first packet only; bytes 1–7: ASCII `KVM2026` |
| `0x7e` | PING | no payload |
| `0x7f` | DISCONNECT | releases virtual input and closes the connection |

On TCP disconnect, Agent releases left/right/middle buttons and all pressed virtual keys. KEY accepts only codes emitted by the Windows client: the main set through F12, numeric-keypad and navigation keys, right Ctrl/Alt, and Win keys. `KEY_POWER`, `KEY_SLEEP`, `KEY_WAKEUP`, and `BTN_*` are rejected. In manual `--right-button-back` mode, a right-button packet maps to `KEY_BACK`; do not use it with Xtralogic RDP.

`KVM2026` is the fixed shared secret of the current protocol and is sent without encryption. Run Agent only on a trusted LAN. Per-installation secrets and HMAC require a coordinated protocol and Windows-client change.

## LAN discovery

Discovery is independent from TCP and uses UDP port 5557. The Windows client sends exact ASCII request `WAKVM_DISCOVER_1` to directed active-adapter IPv4 broadcasts and `255.255.255.255`. Agent replies by UDP unicast to the source address:

```text
WAKVM_REPLY_1|<name>|<ip>|<tcp-port>|1
```

The reply IP is informational; Windows connects to the UDP source address. Discovery packets never contain the TCP authorization key or input commands. Windows removes invalid and duplicate responses. Discovery runs at client startup and when the user clicks Find devices, for about two seconds; it does not run continuously.
