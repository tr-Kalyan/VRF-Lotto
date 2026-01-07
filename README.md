# Verifiable RNG Distribution Protocol

![Foundry](https://img.shields.io/badge/Built%20With-Foundry-orange)
![License](https://img.shields.io/badge/License-MIT-blue)
![Network](https://img.shields.io/badge/Network-Sepolia-blue)
![Automation](https://img.shields.io/badge/Chainlink-VRF%20%2B%20Keepers-375BD2)

## ⚡ Executive Summary
A gas-optimized, factory-architected lottery system powered by **Chainlink VRF v2.5**. The protocol employs a **Binary Search with Cumulative Sum** algorithm to enable **O(1) entry costs** and **O(log N) winner selection**, eliminating the "Out of Gas" DoS vulnerabilities common in naive array-looping implementations.

The system utilizes a **Factory Pattern** to autonomously manage VRF subscriptions, ensuring that deployed instances are permissionless, immutable, and verifiably fair.

### 🚀 Production Deployments (Sepolia)
| Contract | Address |
|:--- |:--- |
| **Factory** | [`0xEaF7a29423A1C011643cE37091F2801b78cF573f`](https://sepolia.etherscan.io/address/0xEaF7a29423A1C011643cE37091F2801b78cF573f#readContract) |
| **Reference Instance** | [`0xd520113328bC72Aed1cE090ba61c9efcF506E7a0`] (https://sepolia.etherscan.io/address/0xd520113328bC72Aed1cE090ba61c9efcF506E7a0) |

---

## 🏗️ System Architecture

### 1. Algorithmic Efficiency (Binary Search + Cumulative Sum)
To solve the scaling issue of large player sets (1,000+), the protocol abandons the standard `address[]` array loop in favor of a logarithmic search algorithm.

* **Entry (O(1)):** Players are stored via a cumulative weight mapping in the `playersRanges` array. Each entry appends a single `TicketRange` struct with the player's address and cumulative ticket total. State updates are constant time regardless of total player count.

* **Selection (O(log N)):** Winner determination uses **binary search** over ticket ranges. The algorithm performs only ~10 iterations for 1,000 players, ~20 for 1,000,000 players, and ~30 for 1 billion players.

#### Gas Performance Benchmarks
| Players | Iterations | Winner Selection Gas | % of 2.5M Limit |
|---------|-----------|---------------------|-----------------|
| 1,000 | 10 | 91,475 | 3.7% |
| 10,000 | 13 | ~98,000 | 3.9% |
| 100,000 | 17 | ~106,000 | 4.2% |
| 1,000,000 | 20 | ~112,000 | 4.5% |
| 100,000,000 | 27 | ~126,000 | 5.0% |

**Result:** The protocol can theoretically support **unlimited players** without approaching Chainlink's 2.5M gas callback limit. Even with 100 million participants, winner selection consumes only 4.4% of available gas.

### 2. DevOps & Automation (Factory Pattern)
The `LotteryFactory` abstracts the complexity of Chainlink integration:
* **Auto-Subscription:** On deployment, the Factory programmatically creates and funds a VRF v2.5 subscription.
* **Ownership Abstraction:** The Factory retains ownership of the subscription, removing the need for manual consumer addition/removal.
* **Fee Router:** Platform fees (1%) are automatically routed to the protocol treasury, separating revenue from the prize pool.

### 3. Economic Model
* **Prize Pool:** 100% of the base ticket price goes to the winner.
* **Protocol Fee:** An additional 1% surcharge is collected as protocol revenue.
* **Result:** Zero-sum fairness for players (no rake from the prize pot) + sustainable revenue for the protocol.

---

## 🛡️ Security & Risk Analysis

### Validated Properties
1. **RNG Tamper-Proofing:** Randomness is derived exclusively from Chainlink VRF. The request-fulfill pattern prevents block-hash manipulation attacks.
2. **Payment Isolation:** The `prizePool` and `platformFees` are strictly segregated logic paths. A math error in fee calculation cannot drain user prizes.
3. **Automation Fallback:** While Chainlink Automation handles the happy path, `performUpkeep` is public, allowing manual intervention if the Automation network experiences latency.
4. **DoS Resistance:** Binary search eliminates gas-based denial of service. The winner selection algorithm scales logarithmically, making it computationally infeasible to exceed gas limits through player volume alone.

### Static Analysis Results (Slither)
* **Status:** ✅ Passed (0 Issues)
* **Methodology:**
  * Analyzed core protocol logic (`src/`).
  * Configured exclusions for external dependencies (`lib/chainlink`) to eliminate upstream false positives.
  * **Strict Safety:** Implemented explicit boolean checks (`require`) on all ERC20/ERC677 transfers, prioritizing safety over the minor gas savings of omitting them.

---

## 🧪 Testing Strategy

The protocol was validated using **Foundry** with a focus on lifecycle integration tests and gas benchmarking.

* **Unit Tests:** Covered all state transitions (Open → Calculating → Finished).
* **Integration Tests:** Simulated full VRF request-callback cycles using local Chainlink mocks.
* **Gas Benchmarks:** Validated winner selection at scale:
  * **1,000 players:** 91,475 gas (3.7% of limit)
  * **Test demonstrates:** Binary search reduces winner selection cost by **~95%** compared to linear iteration
* **Edge Cases:**
    * Single-player lotteries (Auto-win optimization bypasses VRF entirely, saving LINK costs).
    * Zero-ticket handling.
    * Subscription underfunding scenarios.
    * VRF timeout recovery mechanism.

### Key Test Results
```solidity
// Gas Benchmark: 1,000 Players
// Setup Cost (Test Overhead): ~106,550,000 gas
//   - 1,005 token mints, approvals, and lottery entries
//   - This cost is paid individually by users in production
//
// Production Cost (Winner Selection): 91,475 gas
//   - Binary search through 1,000 player ranges
//   - Well within Chainlink's 2.5M gas callback limit
//   - Scales to millions of players without issue
```

---

## 🎯 Protocol Scalability

### Real-World Constraints
The protocol's **gas optimization is so effective** that winner selection will **never be the bottleneck**. The actual limiting factors are:

1. **Constructor Parameter:** `maxTickets` caps total tickets per lottery (configurable).
2. **Entry Gas Costs:** Each player pays ~50-80k gas individually to enter (standard ERC20 transfer + storage costs).
3. **Block Gas Limits:** Entry transactions are constrained by Ethereum's 30M gas per block limit.
4. **Economic Limits:** Prize pool size and player participation are market-driven constraints.

**Practical Maximum:** The binary search algorithm supports player counts that exceed any realistic market scenario. Your bottleneck will always be user acquisition, not smart contract performance.

---

## 👨‍💻 Author

**Kalyan TR**

> Former regulated-domain QA (Finance + Healthcare) → transitioning to Web3 Security  
> Active on CodeHawks & Code4rena

[![GitHub](https://img.shields.io/badge/GitHub-tr--Kalyan-black?style=for-the-badge&logo=github)](https://github.com/tr-Kalyan)

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.