# Historical development references

This publication lineage retains the development order, commit subjects, authored
code, frozen showcase agents, match records, presentation files and engineering
results. Local operational passages were generalized in three reports and one
commit message. Original desktop-voice WAV assets whose redistribution permission
was not established were excluded separately; see [Audio assets](AUDIO_ASSETS.md).

Those transformations, followed by the public email correction, change commit
identifiers across the publication lineage. Current report references identify the
equivalent stages in this public history, with their historical dates and test
outcomes retained. The frozen selection protocol, fixture declarations and
checksum-bound evidence keep the source identifiers recorded when they were
produced. Those identifiers describe historical provenance; they do not promise
that the old commit objects can be checked out from this repository. Frozen
source/file hashes and outcome records are unchanged. No old-object refs or
original-to-current mapping files are shipped.

The exporter dependency pin identifies Bytefray source, rather than this companion
repository, and remains unchanged. Historical test counts describe their original
qualification environment. Current publication checks must be run on the chosen
publication commit. New nonverbal cues are a visible preparation change after
historical sanitation, not a rewritten claim about the previous announcer.

## Known failures at two historical commits

The excluded clips existed in exactly two commits: "feat: arcade match announcer
(opening sequence and victory call)" and "feat: add filled arc memory rendering with
Classic comparison mode". Those commits still contain the code, `voice.json` hashes,
tests and documents that refer to the clips, so checking them out gives an
incomplete announcer:

- The viewer still starts and plays the match (the smoke test passes), but Godot
  logs errors while loading the missing clips. The announcer never plays a clip
  that does not verify, so the spoken parts of the opening and victory call are
  absent.
- `tests/sound_check.gd` fails. No announcer clip verifies against `voice.json`, the
  dependent opening and victory-call checks fail, and the run stops early. Its pytest
  wrapper, `exporter/tests/test_sound.py`, therefore fails too when Godot is present.
- `tests/render_announcer.gd` refuses to render, because the clips do not load.
- `exporter/make_announcer_voice.py --check` and `exporter/tests/test_announcer_voice.py`
  fail because the clips are missing.

All other commits are unaffected. The current tree replaces the bank with the
procedural cues described in [Audio assets](AUDIO_ASSETS.md).
