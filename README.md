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
- **Saved address picker** → Food Rescue cell channel
- **Live MQTT** on Zomato’s consumer broker
- **Time-sensitive notifications** + optional sound
- **Dedup + stale filter** so retained messages don’t spam you
- **Alert cooldown** (configurable)
- **Does not call create-cart** — won’t burn the official in-app pitch
- Keychain session storage · launch at login · polished SwiftUI popover

## Screenshots

Run the app and click the leaf / fork icon in the menu bar (top right).

## Requirements

- macOS 14.0+
- Xcode 16+ (Swift 5.9+)
- A Zomato account with at least one saved delivery address
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you regenerate the project from `project.yml`

## Build & run

```bash
git clone https://github.com/Misterr-H/FoodRescueBar.git
cd FoodRescueBar
open FoodRescueBar.xcodeproj
```

In Xcode:

1. Select the **FoodRescueBar** scheme  
2. Set your **Signing Team** (Signing & Capabilities)  
3. Run (**⌘R**)

Or from the CLI:

```bash
# Optional: regenerate project
# xcodegen generate

xcodebuild -scheme FoodRescueBar -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/FoodRescueBar-*/Build/Products/Debug/FoodRescueBar.app
```

The app has **no Dock icon** — look for it in the **menu bar**.

## How to use

1. Click the menu bar icon  
2. Sign in with your Zomato phone number + OTP  
3. Choose a saved address  
4. Hit **Start listening**  
5. When a cancel fires nearby → macOS alert → open Zomato and claim  

Keep the Mac awake and online. Sleep interrupts MQTT until the reliability loop reconnects.

## Architecture

```
Login (PKCE OAuth phone OTP)
  → GET  /gw/user/info
  → POST /gw/user/location/selection
  → GET  /gw/tabbed-home?cell_id&address_id
  → MQTT SUBSCRIBE food_rescue_cell_<cell>
  → order_cancelled → UserNotifications
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
