# Garmin Dashboard

Self-hosted Garmin health data pipeline and dashboard. Pulls your entire Garmin Connect history into a PostgreSQL database and displays it in a React frontend with charts and an interactive map.

**What you get:**
- Daily stats: steps, calories, stress, body battery, SpO2, resting HR
- Sleep: duration, stages (light/deep/REM), sleep score, respiration
- HRV trends and status
- All activities with GPS route maps, speed/temperature/wind-colored polylines, personal bests
- Touring mode: multi-day trip view with weather overlay, country crossings, sleep locations on map
- Multi-user: each user has isolated data and manages their own Garmin credentials

---

## Requirements

- Docker + Docker Compose
- A Garmin Connect account

---

## Project Structure

```
garmin-dashboard/
â”œâ”€â”€ docker-compose.yml       â† all 4 services (db, sync, api, frontend)
â”œâ”€â”€ .env.example             â† copy to .env and fill in values
â”œâ”€â”€ db/
â”‚   â””â”€â”€ init.sql             â† database schema (auto-applied on first start)
â”œâ”€â”€ sync/
â”‚   â”œâ”€â”€ sync.py              â† main sync loop (runs hourly)
â”‚   â””â”€â”€ db.py                â† database helpers
â”œâ”€â”€ api/
â”‚   â”œâ”€â”€ main.py              â† FastAPI REST backend
â”‚   â”œâ”€â”€ auth.py              â† JWT, bcrypt, Fernet encryption
â”‚   â””â”€â”€ db.py                â† database helpers
â””â”€â”€ frontend/
    â””â”€â”€ src/
        â”œâ”€â”€ App.tsx
        â”œâ”€â”€ components/      â† all chart and UI components
        â”œâ”€â”€ types.ts
        â”œâ”€â”€ api.ts
        â””â”€â”€ stats.ts
```

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/zekicandemiralay/Quarc_Garmin.git
cd Quarc_Garmin
```

### 2. Create your `.env` file

```bash
cp .env.example .env
```

Open `.env` and set:

| Variable | Description |
|----------|-------------|
| `SECRET_KEY` | Encryption key for credentials and JWT tokens â€” **required** |
| `POSTGRES_PASSWORD` | Any password for the local database |

Generate a `SECRET_KEY`:

```bash
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

That's all that's required. Garmin credentials are set per-user through the dashboard UI after first login â€” no `.env` entries needed.

### 3. Start everything

```bash
docker compose up -d --build
```

On **first run** the sync service:
1. Creates the database schema
2. Creates a default admin account (`admin` / `admin`) â€” **change this immediately after login**
3. Waits for Garmin credentials to be set via the dashboard

Watch the logs:

```bash
docker compose logs -f sync
```

### 4. Open the dashboard and finish setup

```
http://localhost:3000
```

Log in with `admin` / `admin`, then:

1. **Change the admin password** â€” user menu (top right) â†’ Settings â†’ Change Password
2. **Set your Garmin credentials** â€” user menu â†’ Settings â†’ Garmin Credentials
   - Stored encrypted; cannot be read back by anyone, including admins
3. **Restart sync** to start the backfill immediately:
   ```bash
   docker compose restart sync
   ```

The sync service will backfill up to 10 years of Garmin history on first run. Subsequent runs sync incrementally (last 7 days + any gaps, every hour).

---

## MFA accounts

If your Garmin account has two-factor authentication enabled, the sync service cannot complete the interactive login automatically. Run this once on the host to pre-generate OAuth tokens:

```bash
python3 garmin_login.py
```

This saves tokens to `garth_tokens/` which is mounted into the sync container. After that, the sync service uses the cached tokens and MFA is not prompted again until they expire.

---

## User management

Admins can create and delete users via user menu â†’ Manage users.

Each user:
- Has completely isolated data (activities, sleep, HRV, tours)
- Sets their own Garmin credentials via Settings â€” no one else can read them back
- Can change their own password

---

## Updating

```bash
git pull
docker compose build
docker compose up -d
```

The sync service runs schema migrations automatically on startup â€” no manual steps needed.

---

## Check what was synced

```bash
docker compose exec db psql -U garmin -d garmin
```

```sql
-- Activity count and date range per user
SELECT u.username, MIN(a.start_time::date), MAX(a.start_time::date), COUNT(*)
FROM activities a JOIN users u ON u.id = a.user_id
GROUP BY u.username;

-- Recent daily stats
SELECT date, steps, resting_hr, body_battery_high FROM daily_summary ORDER BY date DESC LIMIT 7;

-- Sleep last week
SELECT date, sleep_score, round(duration_seconds/3600.0, 1) AS hours FROM sleep ORDER BY date DESC LIMIT 7;
```

---

## API

The REST API runs on port 8000. Interactive docs: `http://localhost:8000/docs`

All data endpoints require a Bearer token obtained from `POST /auth/login`.

**Auth**

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/login` | Login â€” returns JWT token |
| GET | `/auth/me` | Current user info |
| PUT | `/auth/me/password` | Change password |
| PUT | `/auth/me/garmin` | Set Garmin credentials (write-only) |

**Data** (scoped to the authenticated user)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/range` | Earliest and latest dates in DB |
| GET | `/api/daily` | Daily summary (steps, HR, stress, body battery, SpO2) |
| GET | `/api/sleep` | Sleep data (duration, stages, score) |
| GET | `/api/hrv` | HRV data |
| GET | `/api/activities` | Workouts |
| GET | `/api/activities/map` | Activities with GPS polylines |
| GET | `/api/activities/countries` | Stats grouped by country |
| GET | `/api/summary` | 7-day and 30-day aggregated stats |
| GET | `/api/touring` | Touring activities with weather and country crossings |
| GET/POST | `/api/tours` | Named tours (multi-day trips) |
| GET/PUT/DELETE | `/api/tours/{id}` | Tour detail, update, delete |

**Admin**

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/admin/users` | List all users |
| POST | `/api/admin/users` | Create user |
| DELETE | `/api/admin/users/{id}` | Delete user and all their data |

All data endpoints accept optional `start` and `end` query params (`YYYY-MM-DD`).

---

## Stopping / restarting

```bash
docker compose down        # stop (data preserved in volumes)
docker compose up -d       # start again
docker compose down -v     # stop AND delete all data
```
