# Vera — Voice-First Daily Planner

Plan your day in under 5 minutes, hands-free. Speak naturally, and Vera builds a prioritized schedule using your health data and calendar.

---

## How It Works

1. **Tap the mic** — Vera greets you with a health briefing (recovery score, sleep, HRV)
2. **Talk through your day** — tell Vera what you need to get done; it asks smart follow-up questions
3. **Vera organizes your plan** — tasks sorted by priority, with time blocks
4. **Plan written to Google Calendar** automatically

---

## Features

- Voice-only planning via on-device speech recognition and TTS (no internet needed for STT/TTS)
- AI powered by **Groq** (primary, llama-3.3-70b) with **OpenRouter** fallback
- **Whoop** integration — recovery score, strain, HRV, sleep performance
- **Apple HealthKit** — HRV, resting heart rate, sleep
- **Google Calendar** — reads today's events for conflict detection, writes finalized plan
- Siri shortcut: "Hey Siri, start planning"
- Connected Apps screen to manage integrations

---

## Prerequisites

Before you can build and run Vera, make sure you have the following installed and configured.

### System

| Requirement | Version | Notes |
|-------------|---------|-------|
| macOS | 14 (Sonoma)+ | Required to run Xcode 15+ |
| Xcode | 15+ | Install from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835) |
| iOS device or simulator | iOS 17+ | Speech recognition works best on a real device |

### Tools

```bash
# Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# XcodeGen — generates the Xcode project from project.yml
brew install xcodegen
```

### API Accounts

You need accounts (all have free tiers) for:

| Service | Sign-up | What it's used for |
|---------|---------|-------------------|
| **Groq** | [console.groq.com](https://console.groq.com) | Primary AI (llama-3.3-70b, fast & free) |
| **OpenRouter** | [openrouter.ai](https://openrouter.ai) | AI fallback when Groq is rate-limited |
| **Whoop** *(optional)* | [developer.whoop.com](https://developer.whoop.com) | Recovery score, HRV, strain in your greeting |
| **Google Cloud** *(optional)* | [console.cloud.google.com](https://console.cloud.google.com) | Read/write Google Calendar events |

> Groq and OpenRouter are **required**. Whoop and Google Calendar are optional — the app works without them but won't show health context or write events.

### Setting up Google Calendar (optional)

1. Create a project in Google Cloud Console
2. Enable the **Google Calendar API**
3. Create an **OAuth 2.0 Client ID** → Application type: **iOS**
4. Set Bundle ID to `com.planit.app`
5. The redirect URI is automatically: `com.googleusercontent.apps.<your-client-id>:/`

### Setting up Whoop (optional)

1. Go to [developer.whoop.com](https://developer.whoop.com) and register an application
2. Set the redirect URI to `com.planit.app://oauth/whoop`
3. Request scopes: `read:recovery read:sleep read:cycles read:profile offline`
4. Copy your Client ID and Client Secret into `APIKeys.swift`

---

## Local Setup

```bash
# 1. Clone
git clone https://github.com/Xaid-vfx/Vera.git
cd Vera

# 2. Add API keys
# Edit PlanIt/Services/APIKeys.swift and fill in:
#   - APIKeys.groq
#   - APIKeys.openRouter
#   - APIKeys.whoopClientId / whoopClientSecret  (Whoop developer portal)
#   - APIKeys.googleClientId                      (Google Cloud Console, iOS OAuth client)

# 3. Generate Xcode project
xcodegen generate

# 4. Open in Xcode
open PlanIt.xcodeproj

# 5. Select the PlanIt_iOS scheme, pick your simulator or device, and hit Run
```

### Running on Simulator

```bash
# Build
xcodebuild -project PlanIt.xcodeproj -scheme PlanIt_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build

# Find the built .app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "PlanIt.app" \
  -path "*/Debug-iphonesimulator/*" | head -1)

# Install + launch (replace UDID with yours from `xcrun simctl list`)
UDID="6924D5F0-7274-4393-9178-7A86E7667729"
xcrun simctl install $UDID "$APP_PATH"
xcrun simctl launch $UDID com.planit.app
```

### Streaming Logs

```bash
xcrun simctl spawn $UDID log stream \
  --predicate 'subsystem == "com.planit.app"' --level debug
```

---

## Architecture

```
PlanIt/
├── Services/
│   ├── AIService.swift             # Groq + OpenRouter with fallback
│   ├── SpeechRecognitionService.swift  # On-device STT
│   ├── TextToSpeechService.swift   # On-device TTS
│   ├── HealthKitService.swift      # Apple Health
│   ├── WhoopService.swift          # Whoop OAuth2 + V2 API
│   ├── GoogleCalendarService.swift # Google Calendar OAuth2 + read/write
│   ├── VoiceSessionManager.swift   # Core session state machine
│   └── APIKeys.swift               # Bundled credentials (gitignored template)
├── Views/
│   ├── HomeView.swift
│   ├── VoiceSessionView.swift      # Active session UI with waveform
│   ├── PlanResultView.swift        # Finalized plan display
│   ├── ConnectedServicesView.swift # Manage integrations
│   └── OnboardingView.swift        # First-launch OAuth flow
├── Models/
│   ├── HealthContext.swift         # Aggregated health + calendar data for AI
│   └── CalendarEvent.swift
└── Intents/
    └── StartPlanningIntent.swift   # Siri shortcut
```

---

## OAuth Credentials

Each developer needs their own OAuth credentials:

| Service | Where to get |
|---------|-------------|
| Groq | [console.groq.com](https://console.groq.com) — free tier |
| OpenRouter | [openrouter.ai/keys](https://openrouter.ai/keys) — free models available |
| Whoop | [developer.whoop.com](https://developer.whoop.com) — register an app, get Client ID + Secret |
| Google | [console.cloud.google.com](https://console.cloud.google.com) — create an iOS OAuth 2.0 client, enable Calendar API |

For the Google Calendar iOS client, set the redirect URI to the reversed client ID scheme:
`com.googleusercontent.apps.<your-client-id>:/`

---

## License

MIT
