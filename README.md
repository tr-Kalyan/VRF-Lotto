---

# 🏆 Decentralized Weighted Lottery (VRF v2.5)

![Solidity](https://img.shields.io/badge/Solidity-0.8.x-2c2c2c?style=for-the-badge&logo=solidity)
![Foundry](https://img.shields.io/badge/Built%20With-Foundry-ff69b4?style=for-the-badge&logo=ethereum)
![Chainlink VRF](https://img.shields.io/badge/Chainlink-VRF%20v2.5-blue?style=for-the-badge&logo=chainlink)
![Audit Ready](https://img.shields.io/badge/Audit-Ready-green?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)


> **A verifiably fair, gas-efficient lottery system built on Ethereum, powered by Chainlink VRF v2.5, and deployed using the Factory pattern.**
> Every lottery instance is decentralized, tamper-proof, and economically transparent.

---

## ⚙️ Tech Stack

| Component       | Technology                       | Purpose                          |
| --------------- | -------------------------------- | -------------------------------- |
| Smart Contracts | **Solidity (0.8.x)**             | Core logic and VRF integration   |
| Framework       | **Foundry (forge, cast)**        | Development, testing, deployment |
| Randomness      | **Chainlink VRF v2.5**           | Secure and verifiable randomness |
| Security        | **OpenZeppelin ReentrancyGuard** | Protects against reentrancy      |
| Architecture    | **Factory Pattern**              | Scalable contract deployment     |

---

## 🧩 Architecture Overview

The system is composed of two primary contracts:

* **`LotteryFactory`** – Deploys and manages new `Lottery` instances. Handles subscription setup and ownership transfer for Chainlink VRF.
* **`Lottery`** – The actual game logic. Manages participants, ticketing, randomness, and payouts.

This separation makes the system modular, scalable, and easy to verify.

---

### ⚙️ LINK Subscription Assumption

* For simplicity, the current version assumes the **Chainlink VRF subscription** is pre-funded with sufficient LINK.  
* In production, an **automated top-up mechanism** or **dynamic LINK reserve system** would be added.  

* The focus of this project is on **contract integrity, fairness, and DeFi-grade reward flow design**, not off-chain funding logistics.

---

## 🔬 Key Design Choices

### 🎲 1. Weighted Random Selection (Gas Efficient)

Instead of storing each ticket separately (`O(tickets)`), the system stores **unique players only** and tracks their **ticket counts**.

The winner is computed in `O(unique players)` time using a single random value from VRF.

✅ Cheap entries
✅ Predictable gas usage
✅ Fully fair randomness

---

### 💰 2. Isolated Prize & Fee Pools

| Pool           | Purpose                                         |
| -------------- | ----------------------------------------------- |
| `prizePool`    | 100% of ticket value — winner’s reward          |
| `platformFees` | Operational costs (automation & gas incentives) |

By separating pools, the **prize money remains untouched** and auditable.

---

### 🧱 3. Safe Payouts via Pull Pattern

All external transfers follow the **Checks-Effects-Interactions (CEI)** model:

* Balances are updated before transfers
* Payouts are explicitly claimed (pull-based)
* Protected by `ReentrancyGuard`

This guarantees safety against reentrancy or state manipulation.

---

## 🔐 Security Model

| Threat                  | Mitigation                             |
| ----------------------- | -------------------------------------- |
| Randomness manipulation | Chainlink VRF proofs                   |
| Reentrancy              | CEI pattern + OpenZeppelin guard       |
| Gas griefing            | Fixed callback gas limit               |
| Prize pool theft        | Isolated pools & non-upgradable design |
| Centralization risk     | Factory-driven deployments             |

---

## 🚀 Deployment (Sepolia Example)

1. **Deploy the Factory**

   ```solidity
   factory = new LotteryFactory(subId, vrfCoordinator, linkToken, keyHash);
   ```

2. **Create and Fund a VRF Subscription**

   ```solidity
   subId = coord.createSubscription();
   coord.fundSubscription(subId, 100 ether);
   ```

3. **Authorize Factory**

   ```solidity
   coord.requestSubscriptionOwnerTransfer(subId, address(factory));
   factory.acceptSubscriptionOwnerTransfer(subId);
   ```

4. **Deploy a Lottery Instance**

   ```solidity
   factory.createLottery(ticketPrice, duration, maxPlayers);
   ```

---

## 🧠 Lifecycle Overview

| Stage          | Function                         | Triggered By | Description               |
| -------------- | -------------------------------- | ------------ | ------------------------- |
| 🎟 Enter       | `enter()`                        | Player       | Buy tickets               |
| 🔒 Close       | `closeAndRequestWinner()`        | Any user     | Ends entry & requests VRF |
| 🎲 Fulfill     | `fulfillRandomWords()`           | Chainlink    | VRF callback (automated)  |
| 🏁 Finalize    | `finalizeWithStoredRandomness()` | Any user     | Computes winner           |
| 💰 Claim Prize | `claimPrize()`                   | Winner       | Withdraw jackpot          |
| ⚡ Claim Reward | `withdrawTriggerReward()`        | Caller       | Get trigger fee reward    |

---

## 🧪 Testing

Test suite written in **Foundry** covering:

* ✅ Full lifecycle simulation (entry → draw → finalize → payout)
* ⚠️ Guard and revert conditions
* 💸 Fee accounting and prize pool integrity
* 🔍 Randomness verification

```bash
forge install
forge test --via-ir --optimize
```

---

## ✅ Audit Readiness

This project follows **best practices** from CodeHawks and Chainlink’s VRF guidelines:

* Modular and dependency-isolated design
* No unbounded loops or external dependencies during VRF usage
* Strict CEI pattern and minimal state mutation
* Clearly separated user funds and protocol fees

---

## 🧭 Roadmap

* 🔁 Integrate Chainlink Automation for trustless draws
* 🌐 Add a frontend dashboard (React + Wagmi)
* 🎟 Loyalty and staking mechanisms for repeat players

---

## 👨‍💻 Author

**Kalyan TR**
Smart Contract Engineer | Solidity & Web3

[![GitHub](https://img.shields.io/badge/GitHub-tr--Kalyan-black?style=for-the-badge\&logo=github)](https://github.com/tr-Kalyan)

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---
