# Scholaxia Student — Windows Desktop App

Windows desktop client for Scholaxia students with:
- **Login & Signup** (portal design with your Scholaxia images)
- **Live Class** — join live sessions, view upcoming, request sessions
- **School Exam** — teacher-scheduled proctored exams (camera required)
- **CBT Practice** — JAMB/WAEC/NECO practice exams
- **Profile** — view profile & exam setup (JAMB 4 / WAEC-NECO 9 subjects)

Connects to: `https://scholaxia1.onrender.com`

---

## Quick start (recommended — no npm install)

Your Node.js is on **D: drive** (`D:\node.exe`). If C: drive is full, use the Python launcher:

```powershell
cd "c:\Users\EMMA\New folder (2)\scholaxia\scholaxia-desktop"
..\venv\Scripts\pip install pywebview
..\venv\Scripts\python run_desktop.py
```

Or double-click **`START.bat`** — it tries Electron first, then falls back to Python.

---

## Run with Electron (Node on D:)

```powershell
cd scholaxia-desktop
$env:PATH = "D:\;$env:PATH"
$env:npm_config_cache = "D:\tmp\npm-cache"
$env:TEMP = "D:\tmp"
D:\npm.cmd install
D:\node_modules\.bin\electron.cmd .
```

> **Note:** Electron needs ~500MB free disk. If install fails with `ENOSPC`, free space on **C:** or use `run_desktop.py` instead.

---

## Build Windows installer (.exe)

```powershell
$env:PATH = "D:\;$env:PATH"
D:\npm.cmd install
D:\npm.cmd run build
```

Output: `dist/Scholaxia Student Setup.exe`

---

## Screens

| Screen | Description |
|--------|-------------|
| Login | Split layout — statue left, Scholaxia building + portal card right |
| Signup | Same layout, register tab |
| Live Class | Live & upcoming sessions, session requests |
| School Exam | Scheduled proctored exams |
| CBT | Practice exams with timer |
| Profile | Student info + exam setup |

---

## Assets

- `assets/building.png` — Scholaxia building (login background)
- `assets/statue.png` — Statue figure (left panel)
