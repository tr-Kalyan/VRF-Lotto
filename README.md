---

# 🏆 Autonomous Weighted Lottery — Chainlink VRF v2.5

![Solidity](https://img.shields.io/badge/Solidity-0.8.20-black?style=for-the-badge&logo=solidity)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-ff69b4?style=for-the-badge&logo=ethereum)
![Chainlink](https://img.shields.io/badge/Chainlink-VRF%20v2.5%20%2B%20Automation-blue?style=for-the-badge&logo=chainlink)
![Sepolia](https://img.shields.io/badge/Network-Sepolia-brightgreen?style=for-the-badge)
![Verified](https://img.shields.io/badge/Etherscan-Verified-success?style=for-the-badge)

> **A verifiably fair, gas-optimized lottery powered by Chainlink VRF v2.5 and Automation.**  
> Factory-owned subscription • Cumulative sum pattern • 1% platform fee (extra paid by player) • Production-grade security

---

## 🚀 Live on Sepolia

- **Factory**: [`0xBeF17915bBB6fa6956045C7977C17f7fFB86FA49`](https://sepolia.etherscan.io/address/0xBeF17915bBB6fa6956045C7977C17f7fFB86FA49)
- **Example Lottery**: [`0xBD7Aa8f8DC814d3c2a49E92CE08f8d9FaC2C42ec`](https://sepolia.etherscan.io/address/0xBD7Aa8f8DC814d3c2a49E92CE08f8d9FaC2C42ec)
- **VRF Subscription**: Factory-owned (created on deployment)
- **Automation Upkeep**: Manual registration required (once per lottery)

---

## ⚙️ Architecture Overview


### How It Works — Step by Step

1. **You (EOA)**  
   The deployer and sole owner of the `LotteryFactory`. Only you can call `createLottery()` and management functions (`fundSubscription`, `removeConsumer`, etc.).

2. **Factory**  
   - On deployment, automatically creates a Chainlink VRF v2.5 subscription and becomes its permanent owner.  
   - No manual subscription creation or ownership transfer required.  
   - Deploys new `Lottery` instances on demand.  
   - Adds each new lottery as a consumer to the shared subscription.  
   - Distributes all collected platform fees to its owner (you).

3. **Lottery Instances**  
   - Each lottery runs independently with its own ticket sales, deadline, and prize pool.  
   - After the deadline, Chainlink Automation calls `performUpkeep()` (requires manual upkeep registration once per lottery).  
   - `performUpkeep()` sends platform fees to you and requests randomness from Chainlink VRF.  
   - VRF callback selects the winner using the cumulative sum pattern.  
   - Winner claims the full prize pool; you keep the extra 1% platform fee paid by players.

**Result**: A scalable, autonomous lottery system where you maintain full control and collect all fees, while players enjoy verifiably fair randomness powered by Chainlink.


**Key Innovation**: Factory creates and owns the VRF subscription on deployment — no manual ownership transfer required.

---

## 🔬 Core Design Decisions

### Weighted Randomness — Cumulative Sum Pattern

Players are stored with cumulative ticket counts instead of individual tickets.

Example:
| Player | Tickets | Cumulative Total | Ticket Range |
|--------|---------|------------------|--------------|
| P1     | 5       | 5                | 0–4          |
| P2     | 3       | 8                | 5–7          |
| P3     | 2       | 10               | 8–9          |

Winner selection:
1. VRF provides random number
2. `winningTicketId = random % totalSold`
3. Linear search finds the player whose range contains the ID

**Benefits**:
- Entry cost: O(1)
- Winner search: O(unique players) — cheap in practice
- Gas predictable

### Economic Model

- **Ticket Price**: Configurable (e.g., 1 USDC)
- **Player Pays**: `ticketPrice + 1% fee` (e.g., 1.01 USDC per ticket)
- **Prize Pool**: 100% of base ticket price
- **Platform Fee**: 1% of base ticket price (extra paid by player)
- **Owner Profit**: 100% of platform fees

**Design Rationale**:
- Prize pool remains untouched — maximum fairness for players
- Owner earns pure profit from the fee
- Transparent and predictable accounting

### Autonomy

- Chainlink Automation calls `performUpkeep()` after deadline
- Triggers VRF request
- VRF callback selects winner
- Single-player lotteries auto-win (saves LINK)

**Limitation**: Each lottery requires manual upkeep registration on Chainlink Automation UI.

---

## 🔐 Security & Analysis

**Static Analysis (Slither)**:
- Ran Slither on all contracts
- 4 findings — all informational/false positives
- Primary false positive: unchecked LINK token transfers
- **Risk Accepted**: LINK token reverts on failure — no silent failures possible
- No high or critical vulnerabilities

**Key Mitigations**:
- ReentrancyGuard + Checks-Effects-Interactions pattern
- Timestamp dependence mitigated via trusted Chainlink Automation
- Prize pool isolated from fees
- Factory ownership (centralized control — intended design)

---

## 🧪 Testing

- Comprehensive Foundry unit tests
- Full lifecycle coverage: entry → deadline → upkeep → VRF → claim
- Edge cases tested (single player, revert conditions, deadline handling)
- Manual end-to-end verification on Sepolia

```bash
forge test -vvv
```

## 👨‍💻 Author

**Kalyan TR**

> Former regulated-domain QA (Finance + Healthcare) → transitioning to Web3 Security
Active on CodeHawks & Code4rena


[![GitHub](https://img.shields.io/badge/GitHub-tr--Kalyan-black?style=for-the-badge&logo=github)](https://github.com/tr-Kalyan)

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---