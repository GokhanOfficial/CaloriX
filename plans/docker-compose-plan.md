# Docker Compose Support Plan

This project now supports two Docker Compose workflows:

- Development: Vite dev server plus Supabase local stack.
- Production: Vite build served with `vite preview` on port `8080`, without Nginx.

## Files

- `Dockerfile`: development image for the Vite dev server.
- `Dockerfile.prod`: production image that builds the app and serves `dist` with Vite preview.
- `docker-compose.yml`: development compose file.
- `docker-compose.prod.yml`: production compose file.
- `.dockerignore`: excludes local dependencies, build output, Git metadata, and private env files.

## Development

Create a local environment file:

```bash
cp .env.example .env
```

For local Supabase development, use these client-side values in `.env`:

```bash
VITE_SUPABASE_URL="http://localhost:54321"
VITE_SUPABASE_PUBLISHABLE_KEY="your-local-anon-key"
VITE_SUPABASE_PROJECT_ID="local"
```

Start the development stack:

```bash
docker compose up --build
```

URLs:

- App: http://localhost:8080
- Supabase API: http://localhost:54321
- Supabase DB: localhost:54322
- Supabase Studio: http://localhost:54323
- Supabase Inbucket: http://localhost:54324

The Supabase service uses the official Supabase CLI container and mounts the host Docker socket. The CLI creates and manages the local Supabase containers using the existing `supabase/config.toml`, migrations, and functions.

## Production

Create a production environment file:

```bash
cp .env.example .env.prod
```

Set production values in `.env.prod`, especially:

```bash
VITE_SUPABASE_URL="https://your-project-id.supabase.co"
VITE_SUPABASE_PUBLISHABLE_KEY="your-production-anon-key"
VITE_SUPABASE_PROJECT_ID="your-project-id"
```

Start the production container:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up --build
```

URL:

- App: http://localhost:8080

## Notes

- Vite environment variables are embedded at build time for production.
- Do not commit `.env`, `.env.prod`, or other private env files.
- The development app uses polling-friendly settings for reliable hot reload inside Docker.
