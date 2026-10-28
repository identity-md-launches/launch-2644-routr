# ROUTR

A fixed-supply ERC-20 for the ROUTR custom-token launch.

| Property | Value |
| --- | --- |
| Solidity contract | `src/ROUTR.sol:ROUTR` |
| Name / symbol | `ROUTR` / `ROUTR` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer, `msg.sender` |
| Target launch chain | Ethereum, chain ID `1` |

The constructor mints the entire supply once and emits a single
`Transfer(address(0), deployer, supply)` event. For a factory deployment, the
factory receives every token; its caller and transaction origin receive none
automatically. No address, key, service, or post-deployment initialization is
required by this token.

## Behavior and assumptions

The brief specifies a simple token, so transfers follow ordinary ERC-20
semantics. ROUTR inherits the vendored OpenZeppelin ERC-20 implementation without
overriding its transfer or allowance logic. There are no fees, burns, rebases,
transfer restrictions, owner, administrator, upgrade mechanism, or external
minting function. `INITIAL_SUPPLY` is the named constant for the requested supply.
No other economic parameters were chosen.

- `transfer`, `approve`, and `transferFrom` return `true` on success and revert
  with ERC-6093 custom errors on invalid input or insufficient funds/allowance.
- Zero-value transfers between valid accounts succeed and emit `Transfer`.
  Self-transfers preserve balances but still require sufficient funds.
- Transfers to the zero address and approvals to the zero spender revert.
- Approval replaces the previous allowance. Approval of zero revokes it.
  Allowances may exceed the current balance, but spending may not.
- `transferFrom` consumes finite allowances, including transfers back to the
  same account. `type(uint256).max` is treated as unlimited and stays unchanged.
  Even the token holder needs an allowance when using `transferFrom` directly.
- `approve` emits `Approval`. In this implementation, spending allowance through
  `transferFrom` emits `Transfer` without an additional `Approval` event; read
  `allowance` for the current value.
- Failed operations revert all balance and allowance changes. Token operations
  make no external calls and invoke no receiver callbacks.

## Build and check

Run from the repository root with Foundry and Solidity `0.8.26` installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x7769c187a63f5ee68d3f1004acb5972168c96492a71d9917ea2ec1f0339fd156 forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, the Cancun EVM target, optimizer settings
(enabled, 200 runs), and `bytecode_hash = "none"`. It enables neither FFI nor
filesystem permissions. All imported Solidity dependencies and their licenses
are ordinary files under `lib/`; no package installation, submodule, RPC, or
network access is needed to build or test once the pinned compiler is available.
`dependencies.lock.json` records exact upstream tags and SHA-256 hashes for the
downloaded archives and each retained file.

The test suite checks metadata and mint events, factory deployment, exact
transfers, allowance consumption and revocation, zero/self transfers, invalid
addresses, insufficient balances/allowances, rollback, and the absence of
administrative/minting entry points. Five fuzz tests exercise amounts, addresses,
and spending limits with 1,024 runs each. A stateful invariant test runs 128
sequences of 64 operations against an independent balance/allowance ledger.
Each test creates fresh local state and needs no environment variables or fork.
The shell seed above configures Foundry; test contracts do not read or modify
the environment.

The local launch-flow test exercises exact 10% / 85% / 5% transfers, distributor
claims, and transfers into and out of a contract holding pool inventory. It
models token movements only, not Uniswap price formation or swaps. The supplied
protected tests describe a separate launch harness with its own factory,
Uniswap v4 contracts, manifest, and resolved deployment inputs. Those harness
dependencies are not part of this repository; the independent verifier runs that
integration after the manifest is prepared.

## Deployment parameters and responsibilities

Deploy the creation bytecode from `out/ROUTR.sol/ROUTR.json` with no appended
constructor arguments and no ETH. There are no external libraries to link.
The deploying contract must be able to transfer the supply it receives. On this
launch, IdentityMD's factory performs deployment and distribution; this project
provides the token artifact and does not broadcast transactions.

The launch coordinator prepares the manifest separately and records the exact
base-unit supply shown above. The supplied launch economics allocate 10% to the
swarm distributor, 85% to the pool, and 5% to the specified remainder recipient.
The factory handles those movements after construction. The token itself has
no allocation logic, reserved balance, hard-coded launch addresses, or pool
configuration. No application contracts or launch manifest are included here.

## After launch

There are no owner settings or administrative duties on ROUTR. The launch
operator verifies the deployed artifact, metadata, supply, constructor mint
recipient, and subsequent distribution, and publishes the verified source and
contract address. Pool operation and claim distribution belong to the external
launch contracts.

Holders control their own transfers and allowances. Integrators must use
18-decimal base units and handle reverts. Holders should approve only trusted
spenders, limit amounts, and consider resetting a nonzero allowance to zero
before replacing it to reduce the standard ERC-20 approval ordering risk.
There is no administrative recovery for lost keys or mistaken transfers.
Tokens sent to ROUTR itself cannot be recovered. Direct ETH payments revert;
forcibly received ETH and unrelated tokens have no recovery function.

## Security and dependency provenance

The production contract adds only the fixed minting constructor and a supply
constant to [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2).
Only ERC20 and its transitive imports are vendored (MIT).
[forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7) supplies
test helpers (MIT / Apache-2.0). Upstream license files accompany both copies.
The token interface follows [ERC-20](https://eips.ethereum.org/EIPS/eip-20).

The supplied eth-security reference informed review of the supply, access
control, accounting, allowance, and external-call paths. Source review and
Foundry unit, fuzz, and invariant tests are local checks, not an independent
security audit. Slither and Mythril were not run. Independent launch review and
actual pool integration verification remain the launch process's responsibility.
