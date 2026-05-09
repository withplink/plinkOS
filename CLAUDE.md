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
- **Sheet/modal pattern:** Single `Sheet` component used everywhere. Overlay is `position:'absolute', inset:0` with `onPointerDown` that calls `onClose()` and installs a one-time `window` capture listener to swallow the next `click` (prevents background buttons firing after overlay dismisses). Sheet div blocks pointer with `onPointerDown={e=>e.stopPropagation()}`. Sheet div uses `padding:'14px 22px 144px', marginBottom:'-100px'` — NO `overflow:'hidden'` — so the extra 100px extends below the viewport and absorbs spring-back overshoot. Inner scroll area uses `data-scroll` attribute so swipe-to-dismiss pauses when content is scrolled.
- **Swipe-to-dismiss:** `useSwipeToDismiss` hook — direct ref style mutation (no state = 60fps). Dismiss if `delta > 120` or `(delta > 80 && velocity > 0.8)`. Spring-back uses `cubic-bezier(0.34,1.56,0.64,1)`. Entrance animation: `translateY(32px)→0` with same spring curve at `0.3s`.
- **Haptics:** `haptic(ms)` calls `navigator.vibrate?.(ms)` (Android) with `?? _iosHapticLabel.click()` fallback for iOS 18+ (`<input type="checkbox" switch>` trick). Must be called from a user-gesture handler to trigger on iOS.
- **e-ink refresh (~30s):** always run in a background `threading.Thread(daemon=True)` so HTTP returns immediately; show a loading overlay in the frontend
- **Upload:** file picker only — URL upload removed

## Queue System

- `/home/pi/PiInk/config/queue.json`: `{items:[{filename, label, added_at}], current:0, interval:0}`
- Filenames prefixed with timestamp (`YYYYMMDD_HHMMSS_`) to avoid collisions
- `threading.Timer` + `threading.Lock` for auto-rotate
- When queue becomes empty, keep the last file on disk (still showing on e-ink)

## GitHub

- Repo: https://github.com/PixeledCode/pi-ink
- SSH remote: `git@github.com-pcode:PixeledCode/pi-ink.git`
- Based on: https://github.com/tlstommy/PiInk
