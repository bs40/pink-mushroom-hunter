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

## Splash screen

`pmh_splash.png` is the source artwork — two posters side by side. Only the portrait
one is used: the playfield is portrait on every device, so a landscape variant would
not match the game it introduces. `splash-portrait.webp` is the sliced panel, shown
alternating with the home screen every 10 seconds while sitting on the title.

The crop is 483x923 at (0,0). The panel's own right column and bottom row are a bright
anti-aliased fringe against the white page background (mean luminance ~150 against ~40
for real artwork), so they are trimmed — leaving them in put a white hairline down the
edge of the poster.

It ships as a separate file rather than inlined base64. ~116KB encoded into the HTML
would block first paint on a phone, and the game should be playable immediately; until
it loads, the splash phase is skipped and the home screen stays up. WebP at q90 rather
than PNG because the same crop costs 963KB as PNG against 116KB as WebP.

`object-fit` is `contain`, not `cover`: the poster is 1:1.91 and cover would crop it
hard on anything squarer, taking the title with it.

## Boss waves

Odd waves are a mushroom patch, even waves are a boss: 1 patch, 2 boss, 3 patch,
4 boss, and so on.

Wave 2's boss is a giant pink fly agaric at 8x scale (88x80, from the 11x10
flagship sprite). It descends over 60 seconds to a low vibrating drone, and
every 5 seconds it shakes hard from side to side and halts at a random
horizontal position. 100 hits destroys it, in 1,000 multicoloured dots.

Reaching the ship's row costs a life and sends it back to the top. Damage
already dealt is kept, so a lost life sets you back on time rather than wiping
your progress. Landing is fatal whether or not the boss is lined up with you —
otherwise one that had shaken off to the side would sail past into nothing and
the fight could never resolve.

### Every fifth shot

100 hits does not fit the one-shot-in-flight rule: a round trip is roughly
0.55s, so 100 single hits would need about 55 seconds of flawless shooting
against a 60-second descent, with a dozen shake-teleports stealing shots in
flight. So every fifth shot is a wiggly missile worth 5 hits — 4x1 + 1x5 = 9
damage per 5 shots, which brings a perfect run to ~37s and leaves real slack
without touching the signature one-bullet rule.

`BOSS_TYPES` is a registry keyed by type so later waves can host genuinely
different bosses rather than only a bigger mushroom; `bossForWave()` picks the
type and level. Today there is one type, scaling +40 HP and -8s of descent per
level.

### Testing

`?w=N` drops straight into wave N, skipping title and splash — `?w=2` for the
boss, `?w=4` for the level-2 version.

## Layout

```
pink-mushroom-hunter.html   the game
pmh_splash.png              source artwork (both panels)
splash-portrait.webp        the sliced splash poster
deploy-bunny.ps1            bunny.net deployment
```
