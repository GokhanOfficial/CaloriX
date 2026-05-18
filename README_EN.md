# 🔥 CaloriX

<div align="center">

<img src="public/logo.png" alt="CaloriX Logo" width="120" />

**Smart Calorie, Macro Tracking, and AI Nutrition Assistant**

[![Live Demo](https://img.shields.io/badge/Demo-yediginibil.vercel.app-00C7B7?style=flat-square&logo=vercel)](https://yediginibil.vercel.app)
[![GitHub](https://img.shields.io/badge/GitHub-CaloriX-181717?style=flat-square&logo=github)](https://github.com/GokhanOfficial/CaloriX)
[![Version](https://img.shields.io/badge/Version-1.1.0-brightgreen?style=flat-square)](CHANGELOG.md)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

[🇹🇷 Türkçe](README.md)

[🚀 Demo](https://yediginibil.vercel.app) • [📖 Features](#-features) • [📝 Changelog](CHANGELOG.md) • [🛠️ Installation](#️-installation) • [📱 Screenshots](#-screenshots)

</div>

---

## 📖 About

CaloriX is a modern PWA (Progressive Web App) that allows you to track daily calories, macro nutrients, water consumption, and weight. With AI-powered food recognition and the AI Chat nutrition assistant, you can easily track what you eat by taking a photo, typing text, or chatting about your nutrition.

> **Version 1.1.0:** Added the AI Chat nutrition assistant. Removed the offline sync infrastructure because it was causing bugs and data consistency issues.

## ✨ Features

### 🍽️ Food Tracking
- **AI Powered Recognition**: Recognize food via photo or text
- **AI Chat Nutrition Assistant**: Chat about your daily logs, goals, and nutrition decisions for personalized support
- **Barcode Scanning**: Quickly add packaged products via barcode
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
| `VAPID_PRIVATE_KEY` | (Optional) Private Key for Web Push notifications |


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

## 🔧 Technologies

| Category | Technology |
|----------|------------|
| Frontend | React 18, TypeScript, Vite |
| Styling | Tailwind CSS, shadcn/ui |
| State | TanStack Query, React Context |
| Backend | Supabase (PostgreSQL, Auth, Edge Functions) |
| AI | OpenAI GPT-5-Mini, [Pollinations.ai](https://pollinations.ai) |
| Deployment | Vercel |

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
