# ROUTR tests

The token specification is one constructor mint of 1,000,000,000 ROUTR with
18 decimals to the immediate deployer. The tests exercise the real `ROUTR`
contract and its vendored ERC-20 implementation without replacing token storage
or mocking token calls.

`ROUTR.t.sol` retains the existing deployment, metadata, event, distribution,
authorization, and transfer tests. `ROUTR.properties.t.sol` adds boundary and
recovery cases and four fuzz properties, each with 1,024 runs:

- Insufficient allowance with enough balance, including self-transfers.
- Insufficient balance with enough allowance, including self-transfers.
- Approval replacement, spending, and revocation leave other approvals intact.
- Splitting a delegated payment has the same balance and allowance effects as
  sending the aggregate amount once. Exact amount assertions also prevent two
  identically incorrect implementations from satisfying the comparison.

Deterministic cases pin zero, one minor unit, the decimal boundary, the full
supply, `uint256.max - 1`, and `uint256.max`. Reverts are checked against exact
custom errors and arguments. Failure tests also check unchanged state, and a
failed delegated transfer is retried successfully after funding its owner.

## Stateful properties

`ROUTR.invariant.t.sol` extends the existing four-actor handler and independent
balance/allowance ledgers. Initial funding and ring approvals let transfers and
delegated spending reach useful states immediately. Its ten selected actions
mix successful transfers and approvals with balance/allowance overspending,
revocation, invalid zero addresses, and transfer round trips. Invalid calls
must revert as expected; their ghost balances and allowances are not updated.
Expected reverts are consumed inside the handler, and unexpected handler
reverts fail the campaign.

Every step compares all four balances and all sixteen actor allowance pairs
against the ghost ledgers, checks their sum against the fixed supply, and checks
zero-address balances/allowances. All transfer recipients are tracked actors;
the conservation claim relies on that closed recipient set. After each random
sequence, all holders transfer their full balances back to the first actor to
check continued transferability. Inline configuration selects 256 sequences of
128 actions (32,768 randomized handler calls).

The review used the five discovery perspectives in the supplied Pashov fizz
reference and the property review guidance supplied from Trail of Bits:

| Perspective | Property and source basis |
| --- | --- |
| Conservation | Fixed supply from `src/ROUTR.sol:12-15`; balances sum to that supply after every action. |
| State transitions | ERC-20 `approve` and `transferFrom`: replace only the selected approval, spend finite allowances, preserve unlimited allowances, and roll back failed calls. |
| Round trips | Transfers out and back restore balances exactly; intermediate balances must also be correct. No conversion or rounding mechanism exists in this token. |
| Adversarial sequences | Overdrafts, stale/revoked approvals, zero receivers, and self-transfers cannot bypass checks; holders can still transfer everything after a sequence. |
| Token semantics | Existing tests retain constructor recipient, metadata, transfer/approval events, zero transfers, and absence of external mint/admin entry points. |

## Running

With the repository's vendored dependencies and Solidity 0.8.26 available:

```sh
forge build --offline
FOUNDRY_FUZZ_SEED=0x7769c187a63f5ee68d3f1004acb5972168c96492a71d9917ea2ec1f0339fd156 forge test --offline
```

The local suite needs no network, fork, FFI, or account configuration. Existing
factory/distributor/pool-holder examples test ordinary token movements through
contract holders; the supplied protected suite separately exercises the actual
launch and Uniswap pool integration. No implementation defect was reproduced
while extending these tests.
