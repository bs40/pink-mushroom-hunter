# Pink Mushroom Hunter

### Fungal Defence Force

A single-screen arcade shooter in one self-contained HTML file. No build step, no
dependencies, no external assets — open it and play.

**Play it: <https://pinkmushroom.bs40.com>**

---

## What it is

A love letter to the 1979 golden-age formation shooters: a patch of 46 mushrooms
sways at the top of the screen, peels off in looping dives, and shoots at you on
the way down. You get one shot in flight at a time.

Game mechanics aren't copyrightable — names, art, sound and code are. Everything
here is original: sprites are hand-authored as pixel strings in the source, the
5×7 font is hand-built, and all audio is synthesised at runtime with WebAudio.

## The patch

| Points | Enemy | Cap |
| -----: | ----- | --- |
| 60 | Pink fly agaric | Pink with white spots — the only spotted one |
| 50 | Crimson | Broad flat cap with a skirt |
| 40 | Violet | Tall conical |
| 30 | Blue | Small round button |

Every mushroom is worth roughly double while diving. The pink ones dive flanked
by two crimson escorts:

- **150** flagship alone
- **200** with one escort still alive
- **300** with both escorts alive
- **800** if you kill *both escorts first*, then the flagship

Your ship is modelled on the Alpha 7 from *Barbarella* (1968) — pearl hull,
tapered windshield, red side pods.

## Controls

| Key | Action |
| --- | ------ |
| `←` `→` or `A` `D` | Move |
| `Space` / `Z` | Fire (one shot on screen at a time) |
| `P` | Pause |
| `M` | Mute |
| `C` | Toggle CRT scanlines |

On a phone an on-screen pad appears: a fire button, and a pill for steering.
The pill is a *relative* axis — wherever your thumb lands becomes zero, and
only movement from there steers. Resting a thumb on it does nothing, and
absolute position never matters: land on the far right, slide left, and the
ship goes left. Push to the end and the zero point follows, so you never run
out of travel. Deflection is proportional, so small nudges give fine control.

`S` swaps which side the fire button and pill sit on. Since a phone has no `S`
key, the menu line is also tappable. The choice is sticky across sessions.

Extra ship at 7,000 points, then every 30,000. High score persists in
`localStorage`.

## Deploying

`deploy-bunny.ps1` publishes to [bunny.net](https://bunny.net) Edge Storage
behind a CDN pull zone, with a custom hostname and a free Let's Encrypt
certificate.

It needs a bunny.net account API key, read from `$env:BUNNY_API_KEY` or from a
local `.bunny-key` file (gitignored — never commit it).

```powershell
# Phase 1 — storage zone, upload, pull zone, attach hostname
.\deploy-bunny.ps1

# ...add the CNAME the script prints, at your DNS provider...

# Phase 2 — issue the TLS certificate and force HTTPS
.\deploy-bunny.ps1 -Finish

# Later: re-upload after editing, and purge the CDN cache
.\deploy-bunny.ps1 -Update
```

The two phases are separate because Let's Encrypt can't validate the hostname
until DNS already points at the pull zone.

Defaults target `pinkmushroom.bs40.com`; override with `-Hostname` and
`-ZoneName`. Both bunny zone names are globally unique across all customers, so
a name collision fails cleanly and asks you to pick another.

### Two gotchas the script works around

- `$PSScriptRoot` is empty inside a `param()` default when `[CmdletBinding()]`
  is present, so paths are resolved in the script body instead.
- The storage password returned by `POST /storagezone` is not accepted by the
  storage endpoints — the zone has to be re-read to get a working one. Uploads
  also retry with backoff, since a freshly created zone takes a moment to be
  accepted at the edge.

## Splash screens

`pmh_splash.png` is the source artwork: two posters side by side. `splash-portrait.webp`
and `splash-landscape.webp` are the sliced panels (484x924 and 1041x817), picked at
runtime by viewport orientation and alternated with the home screen every 10 seconds.

They ship as separate files rather than inlined base64. At 336KB the encoded payload
would block first paint on a phone, and the game should be playable immediately; if a
poster has not loaded, the splash phase is simply skipped. WebP at q90 rather than PNG
because the same crops cost 2.8MB as PNG.

## Layout

```
pink-mushroom-hunter.html   the game
pmh_splash.png              source artwork for both splash posters
splash-portrait.webp        sliced phone poster
splash-landscape.webp       sliced desktop poster
deploy-bunny.ps1            bunny.net deployment
```
