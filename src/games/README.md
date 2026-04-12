# AutoLoop Demo Games

Five production-quality on-chain games that structurally require
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

| Game             | Fails self-trigger because                                           | Stack                           |
|------------------|----------------------------------------------------------------------|---------------------------------|
| `PitRow`         | Inverted self-interest (loop damages a random floor, nobody wants in) | `AutoLoopVRFCompatible`         |
| `GrandPrix`      | Free-rider + wear negative-EV for most entrants                      | `AutoLoopVRFCompatible`         |
| `SponsorAuction` | Timing-as-attack-surface (adversarial close times)                   | `AutoLoopCompatible` (no VRF)   |
| `PhantomDriver`  | Commit-reveal integrity (reveal must precede resolution)             | `AutoLoopVRFCompatible`         |
| `OracleRun`      | Mempool-snoop attack on VRF outcomes                                 | `AutoLoopVRFCompatible`         |

## Game Summaries

### 1. PitRow — the Decay Tower (flagship answer to Boris)

**File**: `PitRow.sol` · **Tests**: `test/games/PitRow.t.sol` (62 tests)

A persistent on-chain tower where each floor holds a car NFT that
takes catastrophic damage on autonomous VRF ticks. Every tick picks a
random active floor and applies 15–50% damage. Passive decay accrues
between ticks based on wall-clock time since last repair. Unrepaired
floors eventually collapse; insured owners receive 80% of their
insurance premium on collapse.

**Why AutoLoop is structurally required**: the defining property of
PitRow is that **every tick costs someone health**. No rational floor
owner will ever call `progressLoop()` themselves — the VRF output could
pick their own floor. This is the inverted free-rider case: self-triggering
fails because the loop imposes a cost on the only parties with gas to
spend. Only a neutral keeper (AutoLoop) is incentive-aligned to run it.

**Revenue for Lucky Machines**:
- Linear-scaling mint fees → protocol fee balance (admin withdrawable)
- Fixed repair fees → protocol fee balance
- Insurance premiums → insurance pool (80% paid on collapse, 20% retained = long-run edge)

**Key files**:
- `src/games/PitRow.sol` — 400-line contract, extensively commented
- `test/games/PitRow.t.sol` — unit + invariant + fuzz tests

### 2. GrandPrix — Always-On Racing

**File**: `GrandPrix.sol` · **Tests**: `test/games/GrandPrix.t.sol` (44 tests)

Races run on a continuous schedule whether or not anyone is watching.
Players mint cars, enter them in the current race, and at each tick the
loop resolves a power-weighted VRF race. All entrants lose 5–20 power
to wear per race; cars eventually retire when they hit `minPower`.

**Why AutoLoop is structurally required**: two independent reasons.
(1) **Timing as attack surface**: if an entrant could trigger the race
they'd pick the moment the VRF reveal lands in the mempool and only
submit if their car benefits. (2) **Negative-EV free-rider**: every
entrant takes wear, only one wins the pot. Rational entrants reason
"let someone ELSE pay gas." Everyone reasons identically, so nobody
triggers. A neutral paid keeper is the only resolver.

**Revenue for Lucky Machines**:
- Fixed car mint fees → protocol
- 5% rake on every race prize pool → protocol
- Non-custodial winnings (pull-payment for winners)

### 3. SponsorAuction — The Picks-and-Shovels Showcase

**File**: `SponsorAuction.sol` · **Tests**: `test/games/SponsorAuction.t.sol` (37 tests)

A perpetual ascending-bid auction for a single sponsorship slot.
Auctions run back-to-back: when one closes on schedule, the next opens
in the same transaction. The slot winner is entitled to display
sponsorship on the tied asset for `sponsorshipPeriod` seconds.

**Why this one matters for the pitch**: SponsorAuction has **no VRF at
all**. It's the proof that AutoLoop's value extends beyond "Chainlink
VRF + Automation." The auction close is a discrete event with strictly
conflicting incentives — high bidder wants immediate close, prospective
counter-bidders want extension, slot receiver wants close at the peak
bid. No player-controlled trigger is neutral. This is the cleanest
"timing-as-attack-surface" demo in the stack.

**Revenue for Lucky Machines**:
- 5% rake on every winning bid → protocol
- 95% pull-payable to slot receiver (can be delegated to NFT owner)

### 4. PhantomDriver — Commit-Reveal MVP Bet

**File**: `PhantomDriver.sol` · **Tests**: `test/games/PhantomDriver.t.sol` (37 tests)

Players bet on which of four driver archetypes will be named MVP in the
next autonomous race round. Commit phase → reveal phase → VRF resolution,
each gated on block timestamps. Correct predictors split the pot;
unrevealed commits forfeit their stakes to the winners.

**Why AutoLoop is structurally required**: three reasons, any one
sufficient.
1. **Commit-reveal integrity**: reveal must happen *strictly before*
   resolution. If a player triggered the resolution call they could
   resolve mid-reveal-phase after seeing some opponents' reveals but
   before their own.
2. **Adversarial multi-party**: each role's bettors want a different
   trigger time. No player-controlled trigger is fair.
3. **Forfeit free-rider**: unrevealed commits go to the pot. Everyone
   would love to close the reveal window one second before a specific
   opponent can reveal.

This is the sharpest commit-reveal demo in the stack: the cryptographic
pattern **is** the game, and it literally cannot work without a neutral
scheduler.

**Revenue for Lucky Machines**:
- 5% rake on every round pot → protocol
- Forfeited commits → round pot (subsidizes winners, drives participation)
- Rounds with no winners → entire pot to protocol (house edge)

### 5. OracleRun — Autonomous Dungeon Crawl

**File**: `OracleRun.sol` · **Tests**: `test/games/OracleRun.t.sol` (36 tests)

A permadeath dungeon runs on an unchangeable schedule. Players mint
characters, register them for an expedition, and the expedition
resolves on the next VRF tick: each character rolls against the floor's
VRF-derived difficulty. Survivors split the prize pool; dead characters
are permanently flagged. The floor ratchets up after any successful
expedition, increasing future difficulty.

**Why AutoLoop is structurally required**:
1. **Mempool-snoop attack**: a player-controlled trigger lets the player
   compute the resulting VRF output for their own character and only
   submit if they're favored. Only a neutral schedule fires for all
   characters simultaneously.
2. **Death-stalling**: borderline characters want delay, strong
   characters want resolution now — no single trigger time serves both.
3. **Forfeit floor**: the expedition floor advances on survivor success.
   Player-controlled triggers could camp forever at low-difficulty
   floors; a neutral schedule ratchets difficulty honestly.

**Revenue for Lucky Machines**:
- Fixed character mint fees → protocol
- 5% rake on every expedition entry pool → protocol
- Dead character stakes → survivor prize pool
- Wipe rounds (no survivors) → entire pot to protocol

## How to Deploy

The deploy script is `script/DeployGames.s.sol`. It deploys all five
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

1. **Open with SponsorAuction** — non-VRF, non-Racerverse. Runs the
   whole meeting in the background. Investor watches an auction close,
   a new one open, and realizes: "Wait, nobody pushed a button, and
   this couldn't work any other way."

2. **Then PitRow** — the Boris answer. Show that the loop structurally
   cannot be self-triggered because nobody wants the damage. Walk
   through a few ticks: floor 3 takes a hit, floor 7 collapses, a
   salvage pays out. The investor sees that this game does not exist
   without a neutral keeper.

3. **Then GrandPrix** — brand fit, IP leverage. The Racerverse cars
   racing autonomously every 60 seconds. Show the race log on-chain,
   with VRF proofs against a deterministic seed. The "This race
   happened at block 19,847,203. Nobody pressed start" slide.

4. **PhantomDriver as SDK story** — "this is the primitive. Commit-reveal
   prediction markets with autonomous resolution. You can't get this
   from Chainlink Automation + VRF without re-inventing all of
   AutoLoop's coordination."

5. **OracleRun as adjacency** — dungeons, permadeath, character progression.
   Same infrastructure, different flavor, different player segment.

## How to Test

All games share one-shot test invocation:

```bash
forge test --match-contract PitRowTest -vv
forge test --match-contract GrandPrixTest -vv
forge test --match-contract SponsorAuctionTest -vv
forge test --match-contract PhantomDriverTest -vv
forge test --match-contract OracleRunTest -vv
```

Or all at once:

```bash
forge test --match-path "test/games/*" -vv
```

### Test coverage

| Game            | Unit | Invariant | Fuzz | Total |
|-----------------|------|-----------|------|-------|
| PitRow          | 56   | 3         | 3    | 62    |
| GrandPrix       | 41   | 0         | 3    | 44    |
| SponsorAuction  | 35   | 0         | 2    | 37    |
| PhantomDriver   | 35   | 0         | 2    | 37    |
| OracleRun       | 34   | 0         | 2    | 36    |
| **Total**       | **201** | **3**  | **12** | **216** |

All suites pass. Fuzz tests run 256 iterations by default.

## Testing patterns used

Each game contract provides a test harness via a derived contract
(`PitRowHarness`, `GrandPrixHarness`, etc.) that exposes a
`tickForTest(bytes32 randomness)` function. The harness calls the
contract's internal `_progressInternal(randomness, loopID)` directly,
bypassing the ECVRF envelope verification so tests can inject
deterministic randomness without synthesizing valid VRF proofs in
Solidity. VRF-path correctness is covered separately by rejection-path
tests that exercise the envelope with an unregistered controller and
confirm the verification layer rejects the call.

## Architectural notes

- Every VRF game inherits `AutoLoopVRFCompatible`. `SponsorAuction`
  uses `AutoLoopCompatible` (no VRF) — intentional, to show the
  non-VRF path in the stack.
- None of these contracts implement their own `ERC721` — asset
  ownership is tracked in simple `mapping(uint256 => Struct)` state
  to avoid multi-inheritance headaches with AutoLoop's
  `AccessControlEnumerable` base. For a production release we'd
  extract the registry into an ERC721 wrapper.
- Gas profile: standard ticks run in the 90k–200k range depending on
  entrant counts. Well within the 2M default gas cap set at registration.
- Fee handling is deliberately consistent: every game tracks a
  `protocolFeeBalance` + `pendingWithdrawals` split, with admin
  withdrawals and pull-payment claims. This mirrors the pattern in
  `src/sample/RandomGame.sol` and the other existing examples.

## Answering Boris's actions list

From `feedback_esp_boris_actions.md`:

| Action | Addressed by |
|--------|--------------|
| 10. Compelling on-chain game demo requiring continuous autonomous loops + fair randomness | Five games, each a first-class demo |
| 11. Demo clearly shows what Chainlink can't do cleanly | Commit-reveal integrity (PhantomDriver), timing-as-attack-surface (SponsorAuction), inverted self-interest (PitRow) |
| 12. Document the "impossible without AutoLoop" use cases | This README |
| 16. Use cases where self-incentivized triggering doesn't work | Every game here by construction |
| 17. Hybrid model: self-incentivized where possible, AutoLoop where not | SponsorAuction's non-VRF path + the rest's VRF path demonstrate both |

---

*LuckyMachines LLC · Confidential. Last updated 2026-04-11.*
