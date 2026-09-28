# 🔥 CaloriX

<div align="center">

<img src="public/logo.png" alt="CaloriX Logo" width="120" />

**Smart Calorie, Macro Tracking, and AI Nutrition Assistant**

[![Live Demo](https://img.shields.io/badge/Demo-yediginibil.vercel.app-00C7B7?style=flat-square&logo=vercel)](https://yediginibil.vercel.app)
[![GitHub](https://img.shields.io/badge/GitHub-CaloriX-181717?style=flat-square&logo=github)](https://github.com/GokhanOfficial/CaloriX)
[![Flutter](https://img.shields.io/badge/Flutter-1.3.0-blue?style=flat-square)](CHANGELOG.md)
[![PWA](https://img.shields.io/badge/PWA-1.1.0-brightgreen?style=flat-square)](CHANGELOG.md)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

[🇹🇷 Türkçe](README.md)

[🚀 Demo](https://yediginibil.vercel.app) • [📖 Features](#-features) • [📝 Changelog](CHANGELOG.md) • [🛠️ Installation](#️-installation) • [📱 Screenshots](#-screenshots)

</div>

---

> ## 📱 This repository contains two clients
>
> | Path | Status |
> |------|--------|
> | **`flutter_app/`** | **Primary app** — Flutter (Android + web), version **1.3.0**. New features land here. → [Setup & architecture](flutter_app/README.md) |
> | `src/` | React PWA (version 1.1.0) — **maintenance mode**, no new features. This is what the Vercel demo serves. |
>
> Both use the same Supabase backend and the same data model.
> `node tool/check_versions.cjs` compares the two clients' **default goals
> and macro ratios**; a divergence breaks CI.
>
> The features/installation sections below describe the **React PWA**. For the
> primary app's feature list and setup steps see
> [`flutter_app/README.md`](flutter_app/README.md).

---

## 📖 About

CaloriX is a modern PWA (Progressive Web App) that allows you to track daily calories, macro nutrients, water consumption, and weight. With AI-powered food recognition and the AI Chat nutrition assistant, you can easily track what you eat by taking a photo, typing text, or chatting about your nutrition.

> **Version 1.1.0 (React PWA):** Added the AI Chat nutrition assistant. Removed the offline sync infrastructure because it was causing bugs and data consistency issues.
>
> **Version 1.3.0 (Flutter — primary app):** Android port, 12-language UI,
> meal-based reminders, data export/import, forced update gate and **home
> screen widgets**. Details: [CHANGELOG.md](CHANGELOG.md).

## ✨ Features

> The list below is for the **React PWA (1.1.0)**. The primary app's
> (Flutter 1.3.0) features live in
> [`flutter_app/README.md`](flutter_app/README.md).

### 🍽️ Food Tracking
- **AI Powered Recognition**: Recognize food via photo or text
- **AI Chat Nutrition Assistant**: Chat about your daily logs, goals, and nutrition decisions for personalized support
- **Detailed Nutritional Values**: Calories, protein, carbohydrates, fat, and more
- **NOVA & Nutri-Score**: Food processing and nutrition scores

### 💧 Water Tracking
- Daily water consumption goal
- Quick add buttons
- Custom amount entry

### ⚖️ Weight Tracking
- Regular weigh-in reminders
- Weight change charts
- BMI calculation

### 📊 Analytics
- Weekly, monthly, and quarterly trend charts
- Macro distribution analysis
- Goal success rates

### 🔔 Notifications
- Push notification support
- Email reminders
- Customizable notification times

### 🌙 Other
- Dark/Light theme support
- Turkish interface (English support in documentation)
- PWA installation support
- Simpler and more reliable data flow: offline sync has been removed

## 🛠️ Installation

### Requirements

- Node.js 18+
- Bun or npm
- Supabase account

### Steps

1. **Clone the repo**
```bash
git clone https://github.com/GokhanOfficial/CaloriX.git
cd CaloriX
```

2. **Install dependencies**
```bash
bun install
# or
npm install
```

3. **Set up environment variables**
```bash
cp .env.example .env
```

Configure the `.env` file with the following variables:

| Variable | Description |
|----------|-------------|
| `VITE_SUPABASE_URL` | Supabase Project URL |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Supabase Anon Key |
| `VITE_SUPABASE_PROJECT_ID` | Supabase Project ID |
| `OPENAI_API_KEY` | (Optional) OpenAI-compatible API key for AI food recognition and AI Chat |
| `OPENAI_BASE_URL` | (Optional) OpenAI Proxy URL (default: https://gen.pollinations.ai/v1) |
| `OPENAI_MODEL` | (Optional) AI model to use (default: openai) |
| `RESEND_API_KEY` | (Optional) Resend API key for email notifications |
| `VAPID_PUBLIC_KEY` | (Optional) Public Key for Web Push notifications |

### Edge function secrets (set on the Supabase project)

React's `supabase.functions.invoke` calls carry **no secret**: the user's JWT
travels in the `Authorization: Bearer …` header and is verified server-side by
`_shared/auth.ts` → `requireUserContext()`. The cron-driven flow (meal
reminders) has no JWT, so it needs an explicit token:

| Secret | Required? | Description |
|--------|-----------|-------------|
| `INTERNAL_FUNCTION_TOKEN` | **Required in production** | Authorises `check-reminders` → `send-notification`. Generate with `openssl rand -hex 32`. Without it only a `service_role` JWT is accepted. |
| `VAPID_PRIVATE_KEY` | Required for web push | P-256 private key (base64url raw 32 bytes, or PEM). |
| `VAPID_SUBJECT` | Required for web push | `mailto:ops@calorix.app` or `https://calorix.app` — any other form is rejected. |
| `VAPID_PUBLIC_KEY` | Recommended | Derived from the private key when empty. The client reads `VITE_VAPID_PUBLIC_KEY`. |
| `OPENAI_API_KEY` | For AI features | Read server-side by the edge functions. |

Full list and production instructions: [`supabase/.env.example`](supabase/.env.example).

#### Web Push: `VITE_VAPID_PUBLIC_KEY` (client side)

| Variable | Where | Description |
|----------|-------|-------------|
| `VITE_VAPID_PUBLIC_KEY` | `.env` (build time) | `applicationServerKey` for `pushManager.subscribe()`. **Not an edge function secret** — Vite embeds it in the client bundle and it is not confidential. Must be the same key pair as `VAPID_PUBLIC_KEY`. |

If `VITE_VAPID_PUBLIC_KEY` is unset, the push subscription cannot be
created. The React client no longer swallows this silently (the "Enable Push
Notifications" button used to do nothing at all); a visible error with a
"Retry" action is shown instead
(`src/hooks/useNotifications.ts` → `error.operation === 'push'`).

### 🔐 Security note — the session token lives in `localStorage`

The React PWA creates the `@supabase/supabase-js` client with
`storage: localStorage` (`src/integrations/supabase/client.ts`). That keeps
the Supabase session (access + refresh token) **persistently on disk** in the
browser.

| Concern | Reality |
|---------|---------|
| Why it is hard to avoid | This is a **CSR (client-side rendering)** PWA. Moving to `document.cookie` requires SSR or a BFF layer; this repo builds a single-client static Vite bundle, and the edge functions only cover `ai-chat` / `calculate-macros` / `check-reminders` / `send-notification` / `delete-account` — they are not a general proxy. |
| Impact | An **XSS** running on the same origin can read the token from `localStorage` and act as the user. An `httpOnly` cookie is not reachable from XSS. |
| Mitigations | Supabase RLS scopes every table to `auth.uid()`; the `anon` key alone reads no rows. Edge functions independently verify the JWT. No `service_role` key is ever bundled into the client. |
| Roadmap | Move session handling to SSR/BFF. This follows from the React PWA being in **maintenance mode** (`PROTOKOL.md` §0); the primary app is Flutter, which keeps its token in the **Keychain/Keystore**. |

`VITE_SUPABASE_PUBLISHABLE_KEY` (anon) is intentionally shipped to the
client and is **not** a secret; all authorisation lives in RLS and in
edge-function JWT verification.

4. **Start the development server**
```bash
bun dev
# or
npm run dev
```

5. **Open in browser**
```
http://localhost:5173
```

## 🚀 Deployment

### Deploy with Vercel

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https://github.com/GokhanOfficial/CaloriX)

1. Log in to your Vercel account
2. Click the "New Project" button
3. Select the GitHub repo
4. Add environment variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_PUBLISHABLE_KEY`
5. Click the "Deploy" button

### Manual Build

```bash
bun run build
# or
npm run build
```

The build output is created in the `dist/` directory. You can deploy this folder to any static hosting service.

## 🗄️ Database Setup

CaloriX uses [Supabase](https://supabase.com) as its backend.

1. Create a new project on [Supabase](https://supabase.com)
2. Run the migration files in the `supabase/migrations/` folder in the SQL editor
3. Deploy Edge Functions:
```bash
supabase functions deploy
```

## 📝 Release Notes

See [CHANGELOG.md](CHANGELOG.md) for the latest release notes.

## 📦 Android Release & Forced Updates

Android APKs are distributed via GitHub Releases. On launch the app checks the
[`releases/latest/download/latest.json`](https://github.com/GokhanOfficial/CaloriX/releases/latest/download/latest.json)
manifest and behaves based on the device version:

- **Forced update**: If the device build number is below the manifest's
  `minSupportedVersionCode`, the app refuses to open and shows a
  "Update Required" screen until the user installs the APK from the browser.
- **Optional update**: If the device is older than the latest but still
  supported, a dismissible reminder dialog is shown.
- **Check unavailable** (offline): The last successful manifest is cached on
  device, so a decision is still made; with no data at all the app opens with
  a one-time warning.

Release flow:

```bash
# 1) Bump the version in flutter_app/pubspec.yaml: version: 1.3.0+4
#    (keep AppConstants.appVersion, CHANGELOG.md and the version example in
#     this README in sync — node tool/check_versions.cjs is the gate)

# 2) Normal release (older versions get an OPTIONAL update):
tool/release_android.sh --notes-en "Bug fixes" --notes-tr "Hata düzeltmeleri"

# 3) Breaking change such as a DB migration — builds below 3 STOP WORKING:
tool/release_android.sh --min-code 3
```

The script builds the release APK, generates `sha256` + `latest.json` and
uploads both to GitHub Releases. The `--min-code` rule: whenever you migrate
the database (old clients would hit an incompatible schema), pass the first
build number that contains the migration — everything below it gets a forced
update.

## 🔧 Technologies

Both clients share one backend. `flutter_app/` is the **primary app**;
`src/` is the React PWA and is in maintenance mode.

| Category | Primary app (`flutter_app/`) | React PWA (`src/`, maintenance) |
|----------|------------------------------|--------------------------------|
| Frontend | Flutter 3.47 / Dart 3.13 (Android + web) | React 18, TypeScript 5.8, Vite 5 |
| Styling | Material 3 + `app_theme.dart` | Tailwind CSS, shadcn/ui |
| State | Riverpod 2, `go_router` | TanStack Query, React Context |
| Local data | Drift (SQLite) + `shared_preferences` | i18next-http-backend, localStorage |
| Backend | Supabase (PostgreSQL, Auth, Edge Functions) | same |
| AI | OpenAI GPT-5-Mini, [Pollinations.ai](https://pollinations.ai) | same |
| CI | `.github/workflows/flutter.yml` (analyze + test + build) | `.github/workflows/react.yml` (tsc + lint + build) |
| Deployment | GitHub Releases (APK), Flutter web build | Vercel |

## 🌸 AI Supporters

<div align="center">

[![Pollinations.ai](https://pollinations.ai/favicon.ico)](https://pollinations.ai/)

**[Pollinations.ai](https://pollinations.ai/)**

CaloriX is powered by [Pollinations.ai](https://pollinations.ai/) for AI image and text processing capabilities. Pollinations is a free and open-source AI generation platform.

</div>

## 📱 Screenshots

<div align="center">
  <div style="display: flex; justify-content: center; gap: 20px; flex-wrap: wrap;">
    <div style="text-align: center;">
        <img src="docs/screenshots/login.png" alt="Login Screen" width="250" style="border-radius: 20px; box-shadow: 0 4px 8px 0 rgba(0,0,0,0.2);" />
        <p><strong>Login Screen</strong></p>
        <p>User login and registration</p>
    </div>
    <div style="text-align: center;">
        <img src="docs/screenshots/home.png" alt="Home Page" width="250" style="border-radius: 20px; box-shadow: 0 4px 8px 0 rgba(0,0,0,0.2);" />
        <p><strong>Home Page</strong></p>
        <p>Daily summary and quick access</p>
    </div>
    <div style="text-align: center;">
        <img src="docs/screenshots/add-food.png" alt="Add Food" width="250" style="border-radius: 20px; box-shadow: 0 4px 8px 0 rgba(0,0,0,0.2);" />
        <p><strong>Add Food</strong></p>
        <p>AI recognition from photo</p>
    </div>
    <div style="text-align: center;">
        <img src="docs/screenshots/analistics.png" alt="Analytics" width="250" style="border-radius: 20px; box-shadow: 0 4px 8px 0 rgba(0,0,0,0.2);" />
        <p><strong>Analytics</strong></p>
        <p>Trend charts</p>
    </div>
  </div>
</div>

## 🤝 Contributing

We welcome your contributions!

1. Fork the project
2. Create a Feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: Add amazing feature'`)
4. Push the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT license. See the [LICENSE](LICENSE) file for details.

## 👨‍💻 Developer

<div align="center">

**Gökhan Tekyıldırım**

[![Email](https://img.shields.io/badge/Email-gokhantekyildirim%40outlook.com-EA4335?style=flat-square&logo=gmail)](mailto:gokhantekyildirim@outlook.com)
[![GitHub](https://img.shields.io/badge/GitHub-GokhanOfficial-181717?style=flat-square&logo=github)](https://github.com/GokhanOfficial)

</div>

---

<div align="center">

Made with ❤️ in Turkey

**[⬆ Back to Top](#-calorix)**

</div>
