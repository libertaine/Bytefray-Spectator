# P0 showcase selection protocol

Protocol identifier: **`spectator-p0c-showcase-selection-v1`**

Authorization: Project Lead, "Bytefray-Spectator — P0-C Conditional
Authorization", Phase 4 (2026-10-12). The protocol is frozen by the local
commit that adds this file, together with `exporter/showcase_search.py`. The
search records that script's SHA-256 in its ranking output. No candidate seed
is run before that commit exists.

This is **product demonstration work, not scientific evidence** about agent
performance. Nothing selected under this protocol is a research result, and
no claim about the agents' relative strength follows from it.

## 1. Frozen inputs

| Input | Value |
| --- | --- |
| Bytefray | `libertaine/Bytefray` at `9c81718d057c8cd021f6d1cc7938ea19881b78e1` (`bytefray.pin.json`). The 142 files under `engine/src/battle_engine` and `client/src/battle_client` are verified before every run and every export. |
| Agent pool | Exactly two agents, frozen at Spectator commit `4d83cd92d60a332d6a7f1f6936d58aa78a68e96f` |
| `spectator_harrier` | tree `3c36e94f80e36eb59ff90c6ea8dfd127252b587cad2c414fec7a0957429050ae`; `agent.py` `9fafa7098aaa6b022489be1916e51d4405a3ab24db4a1b820be578d6870d1c74`; `agent.yaml` `53c61d02900e6078cb277c49d1b57d49082bbcc4175542c35474e491c1cbaf72` |
| `spectator_bastion` | tree `0958201159a35ccb34481015151280824af4908a5f1b534f176525e814272e75`; `agent.py` `e94dacf66726bd8100aadc38fa55258528dbbfd3378f761b2c6a18837817a600`; `agent.yaml` `e37cf5d7c40ca6022fdb8afceb97caf092a9c62c8117560198d908a0a880a84d` |
| Runner | `exporter/run_match.py` `9823d351b29adfa77d1948131d852730682fae367e5f3ac3ff6ba9bb814fbbe1`. Each run's `match.json` records this SHA-256 and both agents' file digests, which must equal the values above. |
| Exporter | `exporter/spectator_export.py` `8d31e494dc05e7be016d45be9dc0670321ef11373db58a63e1fed04127ddba26` (recorded in every manifest) |
| Search | `exporter/showcase_search.py` (this commit). Its SHA-256 is recorded in `ranking.json`. |

The tree digest is SHA-256 over the lines `<file sha256>  <relative path>\n`
in path order, excluding `__pycache__`, as `run_match.agent_digests` computes
it.

## 2. Ruleset and arena

`bytefray-rules-6-alpha1`; arena 512; action budget 8; tick limit 1000;
seeded core placement (`resolve_direct_match_starts` with no supplied starts,
exactly as `bytefray run` places an alpha1 match); both agents at their
declared parameter defaults (neither declares any); engine `Config` defaults
otherwise (weights alive 1, kill 5, territory 1 per 64 cells; win mode
`score_fallback`).

## 3. Pairings and public seed range

| Pairing | Seat A (the Agent A perspective) | Seat B |
| --- | --- | --- |
| P1 | `spectator_harrier` | `spectator_bastion` |
| P2 | `spectator_bastion` | `spectator_harrier` |

Public seeds **1–500 for each pairing**: 1,000 candidate matches. Every seed
is run; none is skipped or re-run selectively. A run that fails is recorded
as failed and is not retried. The agents were developed only on seeds
900001–900024, which lie outside this range.

Matches run in independent processes (the outputs are deterministic, so the
worker count does not affect any result). Transient outputs go to
`D:\Projects\Bytefray-Spectator-work\p0c-search-v1\`. That location is
outside the Bytefray checkout, outside every Bytefray research directory and
protected evidence path, and outside this repository.

## 4. Hard acceptance filters

A candidate qualifies only if **all** of these hold. Each is computed from
its own artifacts by `candidate_metrics` and `hard_filter_failures`.

| ID | Filter |
| --- | --- |
| H1 | The match ran and produced `replay.jsonl`, `trace.jsonl`, `result.json` and `match.json` |
| H2 | `termination_reason` is `last_agent_standing`: a decisive finish with one survivor (ties, `all_agents_dead` and `tick_limit` fail) |
| H3 | 300 ≤ ticks ≤ 800 |
| H4 | Both entrants made at least one applied WRITE on the other's core region (meaningful activity from both competitors) |
| H5 | Observable sensing: seat A received at least 3 applied SENSE results with contacts, and seat B at least 1 |
| H6 | Legal play: no diagnostics, every action `APPLIED`, and the loser eliminated by `core_captured` |
| H7 | Validation (section 7): the Spectator export verifies, including the corrected sensing playback reconstruction and the outcome checks, and a repeat export is byte-identical |

## 5. Weighted criteria

Each part lies in [0, 1]. The total is the weighted sum (maximum 100).

| Part | Weight | Definition |
| --- | --- | --- |
| contest | 30 | min over the two sides of (ticks ending with at least one of the *other* side's core cells lost) / ticks |
| swings | 20 | min(1, sign changes of (A's own core cells − B's own core cells) per 100 ticks / 20) |
| sensing | 15 | min(positive SENSE results of A, of B) / max(of A, of B) |
| disruption | 15 | min(disruption onsets caused by A, by B) / max(…) |
| length | 10 | max(0, 1 − abs(ticks − 550) / 250) |
| close_finish | 10 | 1 − (winner's own core cells at the end − 1) / 7 |

## 6. Ranking and tie-breaking

Qualifying candidates (H1–H6) are ranked by:

1. higher total;
2. then higher contest;
3. then ticks closer to 550;
4. then lower seed;
5. then P1 before P2.

`ranking.json` (canonical JSON) records the protocol identifier, the search
script's SHA-256, the candidate count, every missing or failed run, the
failure count for each filter, the full ranked list, and **every** candidate
with its metrics, scores and failed filters.

## 7. Validation and selection

1. Candidates are validated **in rank order**, at most 10. Each is exported
   twice into separate directories with the pinned exporter. It passes H7 if
   both exports verify and are byte-identical. The first candidate that
   passes is the **provisional selection**. `validation.json` records every
   attempt.
2. The provisional selection and the next two passing candidates in rank
   order are examined in the Spectator viewer: headless playback of both
   perspectives, the Agent A trace, and the smoke checks. The examination may
   **only** disqualify a candidate for an objective defect: a verification
   failure, a playback or rendering error, or information visible in the
   Agent A perspective that Agent A did not have. It never disqualifies for
   taste. A disqualification is recorded with its evidence, and the next
   candidate in rank order takes its place.
3. The **selected fixture** is the highest-ranked candidate that passes H7
   and the examination. Agent code is never changed in response to any seed.

If no candidate qualifies, the result is reported as such and a separate
protocol revision (v2) is proposed. These filters are not relaxed after the
results are seen.

## 8. Provenance requirements for the selected fixture

- Its four source artifacts with SHA-256, and `match.json` binding the pin,
  seed, configuration, placement and both agents' file digests.
- Its presentation files and manifest, a byte-identical repeat export, and
  the rank, score and metrics from `ranking.json`, cited by that file's
  SHA-256.
- A reproduction: re-running the match from the frozen inputs gives a
  byte-identical `replay.jsonl`. The trace may differ only in `wall_time_ms`,
  and `result.json` only in `completed_at` and `occurrence_id`.
- A selection record (`docs/P0C_SHOWCASE_SELECTION_01.md`) stating the
  rationale and these digests.

## 9. Showcase-fixture seed-governance exception (narrow)

Bytefray's research seed governance (private seed commitments, blinding and
reveal procedures) exists to protect scientific inference. This exception
lets this one product fixture be chosen by a declared public search instead,
and it is limited to:

- the public seeds 1–500 above, with the two frozen showcase agents, under the
  configuration in section 2;
- selecting **one** presentation fixture for the Spectator product
  demonstration.

It does not apply to, and changes nothing about:

- any Bytefray research experiment, seed set, commitment or evidence;
- any research directory or protected evidence path (none is read or
  written);
- E9, which remains LOCKED, and Requirement C, which remains NOT
  ESTABLISHED.

The selected match must never be cited as evidence about agent performance or
about Ruleset properties. The exception is documented publicly with the
fixture.
