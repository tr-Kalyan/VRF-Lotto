# Verifiable RNG Distribution Protocol

![Foundry](https://img.shields.io/badge/Built%20With-Foundry-orange)
![License](https://img.shields.io/badge/License-MIT-blue)
![Network](https://img.shields.io/badge/Network-Sepolia-blue)
![Automation](https://img.shields.io/badge/Chainlink-VRF%20%2B%20Keepers-375BD2)

## ⚡ Executive Summary
A gas-optimized, factory-architected lottery system powered by **Chainlink VRF v2.5**. The protocol employs a **Cumulative Sum (Weighted)** algorithm to enable O(1) entry costs and O(N) winner selection, eliminating the "Out of Gas" DoS vulnerabilities common in naive array-looping implementations.

The system utilizes a **Factory Pattern** to autonomously manage VRF subscriptions, ensuring that deployed instances are permissionless, immutable, and verifiably fair.

### 🚀 Production Deployments (Sepolia)
| Contract | Address |
|:--- |:--- |
| **Factory** | `0xBeF17915bBB6fa6956045C7977C17f7fFB86FA49` |
| **Reference Instance** | `0xBD7Aa8f8DC814d3c2a49E92CE08f8d9FaC2C42ec` |

---

## 🏗️ System Architecture

### 1. Algorithmic Efficiency (Cumulative Sum)
To solve the scaling issue of large player sets (1,000+), the protocol abandons the standard `address[]` array loop.
* **Entry (O(1)):** Players are stored via a cumulative weight mapping. State updates are constant time regardless of total player count.
* **Selection (O(N) Optimized):** Winner determination uses a linear search over ticket ranges. While O(N), this is executed off-chain or via view functions for verification, ensuring the heavy lifting doesn't block critical execution.

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
1.  **RNG Tamper-Proofing:** Randomness is derived exclusively from Chainlink VRF. The request-fulfill pattern prevents block-hash manipulation attacks.
2.  **Payment Isolation:** The `PrizePool` and `FeePool` are strictly segregated logic paths. A math error in fee calculation cannot drain user prizes.
3.  **Automation Fallback:** While Chainlink Automation handles the happy path, `performUpkeep` is public, allowing manual intervention if the Automation network experiences latency.

### Static Analysis Results (Slither)
* **Findings:** 4 (Informational).
* **Analysis:** All findings were flagged as "Unchecked Return Values" on LINK token transfers.
* **Mitigation:** The LINK token contract reverts on failure; manual boolean checks are redundant and were omitted for gas optimization.

---

## 🧪 Testing Strategy

The protocol was validated using **Foundry** with a focus on lifecycle integration tests.

* **Unit Tests:** Covered all state transitions (Open -> Calculating -> Closed).
* **Integration Tests:** Simulated full VRF request-callback cycles using local Chainlink mocks.
* **Edge Cases:**
    * Single-player lotteries (Auto-win optimization).
    * Zero-ticket handling.
    * Subscription underfunding scenarios.


## 👨‍💻 Author

**Kalyan TR**

> Former regulated-domain QA (Finance + Healthcare) → transitioning to Web3 Security
Active on CodeHawks & Code4rena


[![GitHub](https://img.shields.io/badge/GitHub-tr--Kalyan-black?style=for-the-badge&logo=github)](https://github.com/tr-Kalyan)

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.
