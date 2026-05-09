# Piink — Claude Context

## Project

Mobile-first PWA companion app for a Raspberry Pi Zero 2W driving an Inky Impression 7.3" e-ink display. Send photos to the frame from your phone.

## Key Files

- `webserver_new.py` → deployed to `/home/pi/PiInk/src/webserver.py` (Flask backend)
- `main.html` → deployed to `/home/pi/PiInk/src/templates/main.html` (React frontend, single file)

## Deploy Commands

```bash
# Deploy both files and restart
sshpass -p '5409' scp webserver_new.py pi@pi.local:/home/pi/PiInk/src/webserver.py
sshpass -p '5409' scp main.html pi@pi.local:/home/pi/PiInk/src/templates/main.html
sshpass -p '5409' ssh pi@pi.local "echo '5409' | sudo -S systemctl restart piink && echo done"
```

- SSH host: `pi@pi.local`, password: `5409`
- Sudo password: same (`echo '5409' | sudo -S`)
- Service: `piink` (systemd)

## Stack

- **Backend:** Flask on port 80, `host="::"`, `threaded=True`
- **Frontend:** React 18 + Babel standalone (no build step), Jinja2 template
- JSX is wrapped in `{% raw %}...{% endraw %}` to avoid Jinja2 `{{}}` conflicts
- No component library — all UI is hand-rolled with inline styles

## Frontend Architecture

- Single file: all React components, state, and styles live in `main.html`
- Fonts: Instrument Serif (display) + Geist (UI) + Geist Mono (labels)
- 4 palettes: rose / ash / sun / ink (dark)
- Design: cream paper bg, muted rose accent, 1px hairlines, halftone dot textures

## UI Patterns

- **Mobile-first:** touch targets, no hover states
- **Sheet/modal pattern:** overlay is `position:'absolute', inset:0` (covers full screen including behind rounded corners); sheet div is `position:'relative'` with `borderRadius + overflow:'hidden'` outer div and `overflowY:'auto'` inner div
- **e-ink refresh (~30s):** always run in a background `threading.Thread(daemon=True)` so HTTP returns immediately; show a loading overlay in the frontend

## Queue System

- `/home/pi/PiInk/config/queue.json`: `{items:[{filename, label, added_at}], current:0, interval:0}`
- Filenames prefixed with timestamp (`YYYYMMDD_HHMMSS_`) to avoid collisions
- `threading.Timer` + `threading.Lock` for auto-rotate
- When queue becomes empty, keep the last file on disk (still showing on e-ink)

## GitHub

- Repo: https://github.com/PixeledCode/pi-ink
- SSH remote: `git@github.com-pcode:PixeledCode/pi-ink.git`
- Based on: https://github.com/tlstommy/PiInk
