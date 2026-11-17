# MerlinChain MERLIN-01 PoC - BTC address checker accepts consensus-invalid addresses

Foundry proof of concept for a bug bounty report on the MerlinChain
`BTCLayer2Bridge` (proxy `0x28AD6b7dfD79153659cb44C2155cf7C0e1CeEccC`,
implementation v1.6.0, Merlin Chain).

The bridge checks every bridge-out destination with an on-chain BTC
address checker (`0xFFC97EF364077F930A35259134F7Fd9A90D1B126`). The
checker verifies checksums and version bytes but never verifies the
decoded length, so it accepts addresses Bitcoin Core rejects: wrong-length
Base58Check payloads and wrong-length segwit witness programs. Funds
lock or burn with no refund or cancel path.

## What is in here

- `test/TrackA01Fork.t.sol` - fork tests against the live bridge proxy.
  `lockNativeToken` succeeds with invalid addresses and the bridge keeps
  the locked BTC. Controls pass (valid addresses work, bad checksum
  reverts). 7 tests.
- `test/TrackBCheckerFork.t.sol` - fork tests against the live bridge
  proxy (pinned block 33092000). `burnERC20Token` succeeds with invalid
  addresses and the wrapped tokens are burned. 5 tests.
- `test/TrackBUnit.t.sol` - local unit tests against the repo contracts
  (no fork needed). Secondary checks from the audit. 17 tests.
- `src/` - verbatim copies of the bridge contracts from the audited repo
  (`MerlinLayer2/BTCLayer2BridgeContract` @ `899046f2`, v1.6.0), used by
  the unit tests only. The fork tests use the live deployed contracts.

All calls run on a LOCAL fork. No mainnet transaction is sent.

## Run

```sh
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts OpenZeppelin/openzeppelin-contracts-upgradeable

# unit tests (no network needed)
forge test --match-contract TrackBUnitTest

# fork tests (needs a Merlin RPC endpoint)
MERLIN_RPC_URL=https://rpc.merlinchain.io forge test --fork-url https://rpc.merlinchain.io --match-contract "TrackA01ForkTest|TrackBCheckerForkTest" -vvv
```

Expected: 29 passed, 0 failed (7 + 5 fork, 17 unit).

## Key result

These bridge-outs all succeed on the fork (funds locked or burned, no
revert), while a bad-checksum address correctly reverts:

| Destination | Why it is invalid |
|---|---|
| `112edB6q` | base58check, 1-byte payload (must be 20 hash bytes) |
| `bc1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqpqy20t` | v0 segwit, 31-byte program (BIP-141 requires 20 or 32) |
| `bc1qw508d6qejxtdg4y5r3zarvary0c5xwck8mzle` | v0 segwit, 19-byte program |
| `bc1pdg93mv` | v1 segwit, empty program (BIP-350 requires 2-40 bytes) |
| `11GsChQR2U32pvwJcDNPoYHhGcnz5Rv` | base58check, 24 bytes total (must be 25) |

All have valid checksums, so they pass `validBtcAddress` on the live
bridge proxy. Read-only check (no funds needed):

```sh
cast call 0x28AD6b7dfD79153659cb44C2155cf7C0e1CeEccC \
  "validBtcAddress(string)(bool)" "112edB6q" \
  --rpc-url https://rpc.merlinchain.io
# returns true
```
