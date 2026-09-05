# 7. One row order, shared by the sprite, data and save tables

Date: 2026-09-06

## Status

Accepted

## Context

Three independently-built tables identify Digimon: the sprite index (which cell holds which artwork), the packed database (which record holds which stats), and the save format (which byte holds which Digimon's level). Each could plausibly use its own ordering — the sprite packer might sort for atlas locality, the database might keep JSON order, the save might sort by name.

Monkey C has no String→Symbol conversion, by Garmin's stated design, so none of them can be keyed by name at runtime anyway.

## Decision

All three key off **position in `digimonDB.json`**, and nothing re-sorts. The atlas packer may choose *where* a group sits, but the generated `DIGIMON_CELLS` table is indexed by database position.

## Consequences

- A one-row disagreement between any two tables shows the wrong sprite, applies the wrong stats, or corrupts every save — silently, with nothing to catch it.
- The build's verification steps therefore check the tables against the same source ordering rather than against each other.
- Reordering `digimonDB.json` invalidates existing saves. The save's version byte is the only warning mechanism.
