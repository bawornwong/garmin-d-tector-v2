# Data pipeline: JSON to Connect IQ resources

Type: grilling
Status: open
Blocked by: 01, 11

## Question

How do the source's JSON data files reach the watch, and in what runtime shape?

The data: `digimonDB.json` (260 KB, 593 entries), `frontier_rarities.json` (46 KB), `worlds.json` (8.6 KB), `initials.json` (225 B). A Digimon entry carries `number`, `order`, `name`, `stage`, `spiritType`, `abilityName`, `element`, `evolution`, `extraEvolutions[]`, `disabled`, `baseLevel`, `stats{HP,EN,CR,AB}`, `bossStats`, `isPseudo`, `code`.

Decide:

- **Resource form** — `Rez.JsonData`, or a compacted binary table built alongside the sprite blob. 260 KB of JSON parsed into Monkey C dictionaries will not fit comfortably in 768 KB alongside code and sprites; establish what it actually costs.
- **Residency** — is the whole database resident, or looked up on demand from a packed table? The Database app browses all 593 entries; Battle needs one or two at a time.
- **Field packing** — string fields (`name`, `code`, `abilityName`, `evolution`, `extraEvolutions`) dominate the size. Intern them into a string table with numeric references, or keep them inline?
- **Sprite linkage** — how a database entry resolves to its sprite indices in the blob. Must agree with whatever [Sprite atlas layout and index](./05-sprite-atlas-layout.md) decided.
- **Verification** — the build script must prove every one of the 593 entries survives the transform with every field intact. Content fidelity is the whole point.
