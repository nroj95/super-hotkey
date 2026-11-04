# Speaker standby: notes for keeping speakers awake

Some active speakers switch themselves to standby when they hear nothing for a
while, as European ErP energy rules require, and wake on the next sound a few
seconds late, so notifications and the starts of videos go missing. Power-Up
Utilities' *wake speakers* plays a sound to wake them; a planned setting is to
nudge them regularly instead, so they never fall asleep while the user is at
the computer. These notes keep what is known, what was measured and what is
still open, so the defaults can be chosen for most speakers, not one set.

## Known from the manufacturer

Creative's support article on automatic standby (Solution ID 12873,
<https://support.creative.com/kb/ShowArticle.aspx?sid=12873>) lists, among
others, the GigaWorks T20 Series II (MF1610):

- Standby after 10 to 15 minutes without detected audio, on models sold under
  the ErP rules. It is an energy-saving design, not a fault.
- Detection uses a fixed threshold on the incoming signal, so quiet audio can
  count as silence and the speakers can sleep while something is playing.
- Audio above the threshold wakes them.
- No user setting turns standby off; Creative suggests a louder source and
  turning the speakers' own knob down instead.

Creative states neither the threshold nor an exact timer.

## Reported by owners, not confirmed

- Standby after about 10 to 12 minutes; one report says 5.
- Waking takes about 3 to 5 seconds, and short sounds can be lost entirely.
- The power light goes out in standby and comes back on with sound.
- Two separate sets behaved alike, so it is the design, not one faulty unit.

## Measured here

The author's Creative GigaWorks T20 Series II, on the motherboard's 3.5 mm
output.

| Date | What | Result |
| --- | --- | --- |
| 2026-11-04 | Silence after Windows Balloon.wav at the usual volume, until the power light went out | 10 min 53 s |
| 2026-11-04 | Weakest 25 Hz tone that woke them from standby, Windows volume 100 %, speakers' knob at its lowest | -42 dBFS (0.79 % of full scale); not woken at -45 dBFS |
| 2026-11-04 | Power light's delay after that tone began | 1.2 s |
| 2026-11-04 | 25 Hz at -42 and at -36 dBFS, 1.5 s, Windows volume 100 %, knob turned far up | Not heard |
| 2026-11-04 | The same threshold test with the knob at full | -42 dBFS again, light after 1.8 s: the knob does not change detection |

Methods: for the standby time, a script played the sound and timed the silence
until a key press as the light went out, with other sound stopped and Do not
disturb on. For the threshold, with the speakers asleep, a script played
1.5-second sine tones 3 dB apart from -60 dBFS upwards, each followed by an
8-second pause, until a key press as the light came on.

## What the computer cannot know

Over an analog jack nothing comes back from the speakers: Windows sees whether
a plug is in, not whether the speakers are on or asleep, so standby cannot be
detected directly. A microphone near the speakers could tell by listening for a
test sound, but every test sound also resets the speakers' timer.

## Still open

- Whether a tone that wakes them also keeps them awake, so the timer and the
  wake use the same threshold: a long run nudging every 8 minutes.
- Other speakers: Windows' volume scales every signal before the jack, so a
  nudge must be sized for the current volume, measured in decibels, with a
  margin for detectors less sensitive than this one.

## Consequences for the defaults

- **Nudge interval: 8 minutes by default**, below the shortest standby Creative
  states (10 minutes) with room to spare, and configurable for speakers that
  sleep sooner, such as the 5-minute report, or later.
- **Only while the user is at the computer**: unlocked, screens on. Asleep
  away from it, the speakers may save their energy.
- **A volume floor during the nudge**, as *wake speakers* already uses (16 %),
  so a low Windows volume does not hide the signal; the user's level is
  restored at once.
- **The signal: a 25 Hz tone, 6 dB above the threshold found here**, so -36
  dBFS at full Windows volume, scaled up for lower volumes. It woke these
  speakers and stays unheard even turned up loud, below what small speakers
  reproduce. An audible fallback stays for speakers whose detector ignores it.
