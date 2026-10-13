# Announcer listening evaluation (01)

Status: **PENDING**. No human has listened yet. The automated checks
(`tests/sound_check.gd`) cover timing, rules, names and isolation. They
cannot tell whether the voice is understood or sounds right. This
evaluation decides that.

## What to listen to

The files under `docs/announcer_listening/` are the viewer's own runtime
audio, rendered by `tests/render_announcer.gd`. They are 22050 Hz mono WAV
and open in any media player.

| File | Expected (do not read before step 1) |
| --- | --- |
| `01_intro.wav` | Rising rumble, a cut, then "FIGHT!" |
| `02_showcase_ending.wav` | Elimination burst and victory sting, then "BASTION WINS!" |
| `03_call_bastion.wav` | "BASTION WINS!" |
| `04_call_harrier.wav` | "HARRIER WINS!" |
| `05_call_fallback_player_a.wav` | "PLAYER A WINS!" (the call for a winner without a name clip) |

To hear it in the viewer as well:

```powershell
./launch_showcase.ps1 -Play                  # opening sequence from tick 0
./launch_showcase.ps1 -Tick 470 -Play        # the showcase ending and the call
```

## Procedure

1. **Blind transcription.** Play each file once, without reading the
   table above, and write down the words you heard. You may play a file a
   second time; note it if you did.
2. **Character.** For `01` and `02`, rate 1–5:
   - Deep: 1 = normal pitch, 5 = very deep.
   - Gravelly or rough: 1 = clean, 5 = very rough.
   - Obviously computer-generated: 1 = could be human, 5 = clearly a machine.
   - Arcade feel: 1 = none, 5 = strongly evokes classic arcade announcers.
3. **Opening.** In `01` and in the viewer: does the rumble build to the
   word? Is about 3 s too long? Is anything harsh, clipped or unpleasant?
4. **Balance.** In the viewer, at the default 60% volume: is the
   announcer too loud or too quiet against the action effects? Do the
   ending effects mask the call?

A file passes intelligibility when the listener's first-play transcription
matches the expected words. FIGHT and the showcase call (`01`, `02`) must
pass. A failure on `04` or `05` is recorded and fixed before an agent
other than Bastion can win a shown match.

## Notes for the evaluator

- Development used the Windows speech recognizer as a rough
  intelligibility check. It proved unreliable for this purpose: it adapts
  to what it hears, so identical files scored differently over time. It was
  dropped, so its scores are not evidence here.
- FIGHT is the word most at risk. It is short, and its soft "f" was being
  cut off by an earlier trim setting (about 100 ms lost; since fixed).
  Listen for "-ight" or a word that is not "fight".
- If a word fails, the settings are in `exporter/make_announcer_voice.py`
  (`SETTINGS`, `SPOKEN_TEXT`). Rerun it, then `--check`, the tests, and
  `tests/render_announcer.gd`.

## Record

| Listener | Date | Setup (speakers or headphones) | 01 heard | 02 heard | 03 heard | 04 heard | 05 heard | Deep | Gravel | Machine | Arcade | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | | | | | |
