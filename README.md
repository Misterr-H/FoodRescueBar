# FoodRescueBar

Native **macOS menu bar** app that listens for Zomato **Food Rescue** (cancelled nearby orders) and alerts you the moment one appears — so you can open Zomato and claim it in time.

> Unofficial · personal research · not affiliated with Zomato

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI%20MenuBarExtra-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Why

Food Rescue is a race: cancelled orders flash for nearby users for only a few minutes. The official app mostly shows an in-app flyer when you’re already looking. FoodRescueBar sits quietly in your menu bar, keeps an MQTT subscription open for your delivery cell, and fires a macOS notification as soon as an `order_cancelled` event arrives.

## Features

- **Menu bar only** — no Dock icon (`LSUIElement`)
- **Zomato OTP login** (SMS / WhatsApp / Call)
- **Multi-address monitoring** — watch up to 5 saved addresses at once (parallel MQTT)
- **Per-area status** — see which Home / Work / etc. cells are live
- **Live MQTT** on Zomato’s consumer broker
- **Time-sensitive notifications** (include area name) + optional sound
- **Dedup + stale filter** so retained messages don’t spam you
- **Alert cooldown** (configurable)
- **Does not call create-cart** — won’t burn the official in-app pitch
- Keychain session storage · launch at login · polished SwiftUI popover

## Screenshots

Run the app and click the leaf / fork icon in the menu bar (top right).

## Platforms

| Target | Scheme | Notes |
|--------|--------|--------|
| **macOS** | `FoodRescueBar` | Menu bar app (no Dock icon) |
| **iOS** | `FoodRescueBar-iOS` | Full-screen app + local notifications |

### iOS background reality (important)

Apple does **not** allow arbitrary always-on sockets. FoodRescueBar-iOS:

- Delivers **real-time** alerts while the app is **open** or briefly backgrounded  
- Uses background tasks / refresh to reconnect when possible  
- Cannot guarantee MQTT while the phone is locked for hours without a push server  

For best results on iPhone: start listening, allow notifications, leave the app in the foreground or in Recents with **Low Power Mode off**. For desk use, the **macOS menu bar app** remains the most reliable 24/7 listener.

## Requirements

- macOS 14.0+ and/or iOS 17.0+
- Xcode 16+ (Swift 5.9+)
- Apple Development signing (free team works for personal device install)
- A Zomato account with at least one saved delivery address
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you regenerate the project from `project.yml`

## Build & run

```bash
git clone https://github.com/Misterr-H/FoodRescueBar.git
cd FoodRescueBar
xcodegen generate
open FoodRescueBar.xcodeproj
```

### macOS

1. Scheme **FoodRescueBar**  
2. Signing Team → Run (**⌘R**)  
3. Use the menu bar icon (top right)

```bash
xcodebuild -scheme FoodRescueBar -configuration Debug -destination 'platform=macOS' build
```

### iOS (device)

1. Scheme **FoodRescueBar-iOS**  
2. Select your iPhone  
3. Signing Team → Trust developer on device if prompted  
4. Run (**⌘R**) · allow **Notifications**

```bash
xcodegen generate
xcodebuild -scheme FoodRescueBar-iOS -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates build
```

## How to use

1. Click the menu bar icon  
2. Sign in with your Zomato phone number + OTP  
3. **Multi-select** saved addresses (Home, Work, … — max 5)  
4. Hit **Start listening** — each area gets its own MQTT subscription  
5. When a cancel fires near any watched cell → alert names the area → open Zomato and claim  

Stop listening before editing the address set.

### Mac sleep / closed lid

MQTT only works while the Mac is **awake and online**.

| Situation | Alerts? |
|-----------|---------|
| Lid open, Mac awake | Yes |
| Display sleeps but system stays up | Usually yes (with **Keep Mac awake while listening**) |
| **Lid closed** (typical MacBook) | **No** — machine usually sleeps, network dies |
| After wake | App reconnects automatically |

**Workarounds for closed-lid listening:**

1. **Clamshell mode:** power adapter + external display/keyboard (Mac stays awake with lid closed)  
2. Leave lid slightly open  
3. Desktop/Mac mini left on  
4. Settings → enable **Keep Mac awake while listening** (helps idle sleep; not a guarantee for lid-close on battery)

```bash
# Optional system-level (AC power): prevent idle sleep while testing
caffeinate -dims &
```

## Architecture

```
Login (PKCE OAuth phone OTP)
  → GET  /gw/user/info
  → POST /gw/user/location/selection
  → for each selected address:
       GET  /gw/tabbed-home?cell_id&address_id
       MQTT SUBSCRIBE food_rescue_cell_<cell>   (own SSL connection)
  → order_cancelled → UserNotifications (tagged with area name)
```

**Intentionally not called:** `POST /gw/gamification/food-rescue/create-cart` (pitch-once on Zomato’s side).

Inspired by public reverse‑engineering writeups and [jomato-mobile](https://github.com/jatin-dot-py/jomato-mobile).

## Project layout

```
FoodRescueBar/
├── project.yml                 # XcodeGen spec
├── FoodRescueBar.xcodeproj     # Open this in Xcode
├── Sources/
│   ├── FoodRescueBarApp.swift
│   ├── AppState.swift
│   ├── Models/
│   ├── Services/               # Auth, API, MQTT, Keychain, notifications
│   ├── Views/
│   └── Theme/
└── Resources/
```

## Disclaimer

- **Not affiliated** with Zomato / Eternal Ltd.  
- Uses **unofficial private APIs** reverse‑engineered from the mobile app.  
- Likely **against Zomato Terms of Service**.  
- Risk of account restriction. Use at your own risk.  
- Tokens stay on-device in Keychain; this project has no backend.  
- For educational / personal research purposes only.

## License

MIT — see [LICENSE](LICENSE).
