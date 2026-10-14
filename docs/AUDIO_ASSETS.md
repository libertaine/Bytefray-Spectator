# Audio in this Early Preview

The bundled audio is original procedural PCM, generated entirely from this
project's oscillator formulas. There are no sampled voices, trained speech models,
third-party recordings or synthesized Microsoft speech outputs in this publication
history. The nine cue labels identify electronic motifs, **not spoken words**.
Opening FIGHT and winner-name/WINS sequences retain the same verified-record
scheduling, pause/seek/mute behavior and Agent A information boundary.

`audio/announcer/voice.json` uses `bytefray.spectator.announcer` schema version 2,
`nonverbal-procedural` kind and generator `spectator-announcer-cues-v2`. It records
MIT provenance and every raw/processed hash. The legacy `voice` and word-label
fields are retained for the playback bank; their names do not imply speech.

The earlier development implementation used Microsoft David Desktop. Applicable
permission for public redistribution and unrestricted reuse of that output was
not established. [Microsoft's product-specific license terms](https://www.microsoft.com/en-us/useterms)
require identifying the applicable product agreement; community answers and Azure
service terms do not establish desktop-voice output rights. No conclusion that
those original clips are MIT is made here. All 18 original raw/processed WAVs and
five related listening WAVs were excluded across the publication lineage. They
were not converted or relabeled as new assets.

Historical reports, original hash declarations and test outcomes remain factual
records of that earlier development environment. The old desktop-voice artifacts
are absent, so checking those old commits cannot reproduce their audio checks; the
two affected commits and their failing checks are listed in
[Historical provenance](HISTORY_PROVENANCE.md). The former speech generator
(`exporter/make_announcer_voice.py` and `exporter/announcer_sapi.ps1`) is no longer
in the current tree. Current cues have their own truthful manifest and independent
deterministic checks.

To verify or regenerate the current original bank with Python 3.13:

```powershell
python exporter/make_arcade_cues.py --check
python exporter/make_arcade_cues.py --regenerate
```

Neither command needs Windows SAPI or a network connection. Human listening and
accessibility evaluation remain pending; electronic motifs do not communicate
spoken names. Textual entrant labels and recorded result remain visible in Broadcast.
