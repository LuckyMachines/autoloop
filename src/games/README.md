# AutoLoop Demo Games

Eleven production-quality on-chain games that structurally require
AutoLoop's autonomous-loop + fair-randomness combination. Each one
answers a specific weakness Boris Stanic identified in the ESP Office
Hours rejection (2026-04-06).

## The Core Constraint

Boris's sharpest critique was:

> "Many on-chain actions (liquidations, arb, fee collection) work because
> triggering them is self-incentivizing. If AutoLoop targets games, can
> game design incentivize players to trigger progression themselves?"

Every game here is designed to **fail that test**. None of them can be
safely self-triggered by players, and each one fails for a different
structural reason. The games collectively demonstrate that AutoLoop is
not a "better Chainlink Automation" — it's infrastructure for a class
of experiences that self-incentivized keepers cannot support.

| Game               | Fails self-trigger because                                           | Stack                           |
|--------------------|----------------------------------------------------------------------|---------------------------------|
| `CrumbleCore`          | Inverted self-interest (loop damages a random floor, nobody wants in) | `AutoLoopVRFCompatible`         |
| `GladiatorArena`       | Free-rider + wound negative-EV for most entrants                     | `AutoLoopVRFCompatible`         |
| `MechBrawl`            | Free-rider + hull-damage negative-EV for most entrants               | `AutoLoopVRFCompatible`         |
| `SorcererDuel`         | Free-rider + mana-drain negative-EV for most duelists                | `AutoLoopVRFCompatible`         |
| `KaijuLeague`          | Free-rider + damage negative-EV for most entrants                    | `AutoLoopVRFCompatible`         |
| `VoidHarvester`        | Free-rider + integrity-decay negative-EV for most probes             | `AutoLoopVRFCompatible`         |
| `SponsorAuction`       | Timing-as-attack-surface (adversarial close times)                   | `AutoLoopCompatible` (no VRF)   |
| `GladiatorOracle`      | Commit-reveal integrity + cross-contract dual-gate (no VRF)          | `AutoLoopCompatible`            |
| `OracleRun`            | Mempool-snoop attack on VRF outcomes                                 | `AutoLoopVRFCompatible`         |
| `KaijuOracle`          | Commit-reveal + cross-contract: both reveal window AND clash must close | `AutoLoopCompatible`          |
| `ForecasterLeaderboard`| 4-way coordination failure: adversarial timing, 3-hop dependency, free-rider gas, prize-pool timing attack | `AutoLoopCompatible` |

## Game Summaries

### 1. CrumbleCore — the Decay Tower (flagship answer to Boris)

**File**: `CrumbleCore.sol` · **Tests**: `test/games/CrumbleCore.t.sol` (67 tests)

A persistent on-chain tower where each floor takes catastrophic damage on
autonomous VRF ticks. Every tick picks a random active floor and applies
15–50% damage. Passive decay accrues between ticks based on wall-clock time
since last repair. Unrepaired floors eventually collapse; insured owners
receive a salvage payout on collapse.

**Why AutoLoop is structurally required**: every tick costs someone health.
No rational floor owner will ever call `progressLoop()` themselves — the VRF
output could pick their own floor. This is the inverted free-rider case.

### 2. GladiatorArena — Always-On Colosseum

**File**: `GladiatorArena.sol` · **Tests**: `test/games/GladiatorArena.t.sol` (44 tests)

Bouts run on a continuous schedule. Players mint gladiators, enter them in
the current bout, and at each tick the loop resolves a vitality-weighted VRF
bout. All entrants lose 5–20 vitality to wounds per bout.

**Why AutoLoop is structurally required**: (1) timing as attack surface —
entrants could pick favorable VRF reveals. (2) Negative-EV free-rider —
everyone takes wounds, only one wins.

### 3. MechBrawl — Iron Pit Combat

**File**: `MechBrawl.sol` · **Tests**: `test/games/MechBrawl.t.sol` (44 tests)

Brawls run on a continuous schedule. Players deploy mechs, join brawls, and
at each tick the loop resolves an armor-weighted VRF brawl. All entrants
take 5–20 hull damage per brawl.

**Why AutoLoop is structurally required**: same structural pattern as
GladiatorArena — hull damage is negative-EV for all but the winner.

### 4. SorcererDuel — Arcane Circle Duels

**File**: `SorcererDuel.sol` · **Tests**: `test/games/SorcererDuel.t.sol` (44 tests)

Duels run on a continuous schedule. Players summon sorcerers, enter duels,
and at each tick the loop resolves a mana-weighted VRF duel. All duelists
lose 5–20 mana per duel.

**Why AutoLoop is structurally required**: mana drain is negative-EV for all
but the winner — identical structural argument to the other attrition games.

### 5. KaijuLeague — Monster League Clashes

**File**: `KaijuLeague.sol` · **Tests**: `test/games/KaijuLeague.t.sol` (44 tests)

Clashes run on a continuous schedule. Players hatch kaiju, enter clashes,
and at each tick the loop resolves a health-weighted VRF clash. All entrants
take 5–20 health damage per clash.

**Why AutoLoop is structurally required**: health attrition makes
self-triggering negative-EV for all but the winner.

### 6. VoidHarvester — Deep Anomaly Missions

**File**: `VoidHarvester.sol` · **Tests**: `test/games/VoidHarvester.t.sol` (44 tests)

Missions run on a continuous schedule. Players deploy probes, launch them
into missions, and at each tick the loop resolves an integrity-weighted VRF
mission. All probes lose 5–20 integrity per mission.

**Why AutoLoop is structurally required**: integrity decay is negative-EV
for all but the winning probe — the same free-rider structure applies.

### 7. SponsorAuction — The Picks-and-Shovels Showcase

**File**: `SponsorAuction.sol` · **Tests**: `test/games/SponsorAuction.t.sol` (37 tests)

A perpetual ascending-bid auction for a single sponsorship slot. Auctions
run back-to-back: when one closes on schedule, the next opens in the same
transaction.

**Why this one matters for the pitch**: SponsorAuction has **no VRF at all**.
It's the proof that AutoLoop's value extends beyond "Chainlink VRF + Automation."
The auction close is a discrete event with strictly conflicting incentives.

### 8. GladiatorOracle — Bout Prediction Market

**File**: `GladiatorOracle.sol` · **Tests**: `test/games/GladiatorOracle.t.sol` (42 tests)

A commit-reveal prediction market layered on GladiatorArena. Players commit
a secret hash of their predicted bout winner, reveal before the bout resolves,
and split the pot if they called it right.

**Why AutoLoop is structurally required**: settlement requires both the reveal
window to close AND the bout to resolve in GladiatorArena. A player-controlled
trigger could fire the instant the bout resolves, before all reveals are in.

### 10. KaijuOracle — Clash Prediction Market

**File**: `KaijuOracle.sol` · **Tests**: `test/games/KaijuOracle.t.sol` (42 tests)

Commit-reveal prediction market on KaijuLeague clashes. Same pattern as
GladiatorOracle but feeds into ForecasterLeaderboard as the middle hop in
the 3-contract chain.

**Why AutoLoop is structurally required**: dual-gate — both reveal window AND
KaijuLeague clash must resolve before settlement can fire. A player could
trigger settlement the instant the clash resolves, skipping reveals.

### 11. ForecasterLeaderboard — 3-Contract Chain Terminus

**File**: `ForecasterLeaderboard.sol` · **Tests**: `test/games/ForecasterLeaderboard.t.sol` (32 tests)

Reads settled KaijuOracle rounds, scores per-address prediction accuracy
across seasons, and distributes a weekly prize pool to top forecasters.

**Why AutoLoop is structurally required**: four independent coordination
failures — (1) adversarial distribution timing, (2) 3-hop cross-contract
dependency, (3) free-rider on processing gas, (4) prize-pool timing attack.

### 9. OracleRun — Autonomous Dungeon Crawl

**File**: `OracleRun.sol` · **Tests**: `test/games/OracleRun.t.sol` (36 tests)

A permadeath dungeon runs on an unchangeable schedule. Players mint
characters, register them, and each expedition rolls against VRF-derived
difficulty. Survivors split the prize pool; dead characters are permanent.

**Why AutoLoop is structurally required**: player-controlled trigger lets
the caller compute VRF outcomes before submitting and only proceed when
favored.

## How to Deploy

The deploy script is `script/DeployGames.s.sol`. It deploys all eleven
games, registers them with the provided `AutoLoopRegistrar`, and funds
each with `FUND_AMOUNT` wei.

```bash
export PRIVATE_KEY=0x...
export REGISTRAR_ADDRESS=0xDA2867844F77768451c2b5f208b4f78571fd82C1   # Sepolia
export SLOT_RECEIVER=0x...                                           # any EOA
export FUND_AMOUNT=100000000000000000                                # 0.1 ETH each
forge script script/DeployGames.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

After deployment, the worker fleet (in `autoloop-worker/`) will pick up
each registered game on its next poll and begin running its loop.

## How to Demo for Investors

The recommended narrative arc is:

1. **Open with SponsorAuction** — non-VRF, non-combat. Runs the whole
   meeting in the background. Investor watches an auction close, a new
   one open, and realizes: "Wait, nobody pushed a button, and this
   couldn't work any other way."

2. **Then CrumbleCore** — the Boris answer. Show that the loop structurally
   cannot be self-triggered because nobody wants the damage. Walk through
   a few ticks: floor 3 takes a hit, floor 7 collapses, a salvage pays out.

3. **Then any attrition game** (e.g., GladiatorArena) — "Same negative-EV
   free-rider mechanic, different theme. Same contracts, different skins."
   The five attrition games prove the pattern generalizes.

4. **GladiatorOracle as SDK story** — "this is the primitive. Commit-reveal
   prediction markets with cross-contract autonomous resolution. You can't
   get this from Chainlink Automation + VRF without re-inventing all of
   AutoLoop's coordination. And KaijuOracle feeds ForecasterLeaderboard —
   three contracts, one keeper."

5. **OracleRun as adjacency** — dungeons, permadeath, character progression.
   Same infrastructure, different flavor, different player segment.

## How to Test

All games share one-shot test invocation:

```bash
forge test --match-contract CrumbleCoreTest -vv
forge test --match-contract GladiatorArenaTest -vv
forge test --match-contract MechBrawlTest -vv
forge test --match-contract SorcererDuelTest -vv
forge test --match-contract KaijuLeagueTest -vv
forge test --match-contract VoidHarvesterTest -vv
forge test --match-contract SponsorAuctionTest -vv
forge test --match-contract GladiatorOracleTest -vv
forge test --match-contract OracleRunTest -vv
forge test --match-contract KaijuOracleTest -vv
forge test --match-contract ForecasterLeaderboardTest -vv
```

Or all at once:

```bash
forge test --match-path "test/games/*" -vv
```

### Test coverage

| Game                   | Unit | Invariant | Fuzz | Total |
|------------------------|------|-----------|------|-------|
| CrumbleCore            | 59   | 5         | 3    | 67    |
| GladiatorArena         | 41   | 0         | 3    | 44    |
| MechBrawl              | 41   | 0         | 3    | 44    |
| SorcererDuel           | 41   | 0         | 3    | 44    |
| KaijuLeague            | 41   | 0         | 3    | 44    |
| VoidHarvester          | 41   | 0         | 3    | 44    |
| SponsorAuction         | 35   | 0         | 2    | 37    |
| GladiatorOracle        | 40   | 0         | 2    | 42    |
| OracleRun              | 34   | 0         | 2    | 36    |
| KaijuOracle            | 40   | 0         | 2    | 42    |
| ForecasterLeaderboard  | 30   | 0         | 2    | 32    |
| **Total**              | **443** | **5** | **27** | **476** |

All suites pass. Fuzz tests run 256 iterations by default.

## Testing patterns used

Each game contract provides a test harness via a derived contract
(`CrumbleCoreHarness`, `GladiatorArenaHarness`, etc.) that exposes a
`tickForTest(bytes32 randomness)` function. The harness calls the
contract's internal `_progressInternal(randomness, loopID)` directly,
bypassing the ECVRF envelope verification so tests can inject
deterministic randomness without synthesizing valid VRF proofs in
Solidity.

## Architectural notes

- Every VRF game inherits `AutoLoopVRFCompatible`. `SponsorAuction`
  uses `AutoLoopCompatible` (no VRF) — intentional, to show the
  non-VRF path in the stack.
- The five attrition games (GladiatorArena, MechBrawl, SorcererDuel,
  KaijuLeague, VoidHarvester) share identical structural mechanics with
  theme-specific naming throughout. They are deliberately separate
  contracts to demonstrate the breadth of applicable game themes.
- Gas profile: standard ticks run in the 90k–200k range depending on
  entrant counts. Well within the 2M default gas cap set at registration.

## Answering Boris's actions list

From `feedback_esp_boris_actions.md`:

| Action | Addressed by |
|--------|--------------|
| 10. Compelling on-chain game demo requiring continuous autonomous loops + fair randomness | Nine games, each a first-class demo |
| 11. Demo clearly shows what Chainlink can't do cleanly | Commit-reveal integrity (GladiatorOracle), timing-as-attack-surface (SponsorAuction), inverted self-interest (CrumbleCore), 3-contract chain (ForecasterLeaderboard) |
| 12. Document the "impossible without AutoLoop" use cases | This README |
| 16. Use cases where self-incentivized triggering doesn't work | Every game here by construction |
| 17. Hybrid model: self-incentivized where possible, AutoLoop where not | SponsorAuction's non-VRF path + the rest's VRF path demonstrate both |

---

*LuckyMachines LLC · Confidential. Last updated 2026-04-12.*
