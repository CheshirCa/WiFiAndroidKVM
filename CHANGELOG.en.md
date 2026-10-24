# Change Log

This is the English companion to the detailed Russian [CHANGELOG.md](CHANGELOG.md).

## 0.4.6 — 2026-10-13

- Moved dynamically discovered language choices into a dedicated tray submenu.

## 0.4.5 — 2026-10-13

- Replaced the separate Russian language file with `WiFiAndroidKVM.lng`.
- The client reads language sections at startup, saves the selected section code, and falls back to built-in English for empty or absent values.

## 0.4.4 — 2026-10-13

- Updated the Windows client title to match the release version.

## 0.4.3 — 2026-10-13

- Moved manual TCP connection work off the UI thread.
- Released held Android keys during disconnect, improved keyboard suppression, high-resolution wheel handling, cursor confinement, and Russian UI labels.

## 0.4.2 — 2026-10-13

- Hardened the Android Agent against stalled TCP clients and shutdown hangs.
- Returned the actual Agent port in discovery, limited virtual keyboard codes, and refreshed the compact Windows layout.

## 0.4.1 — 2026-10-12

- Fixed numeric-keypad Delete for RDP and Windows modifier cleanup after leaving remote control.

## 0.4.0 — 2026-10-12

- Added license, copyright link, Windows icon, source-free Retail packaging, localization, silent launch, and autostart.
