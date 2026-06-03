# Decentralized Stablecoin System

A minimal, exogenous, algorithmic stablecoin system pegged to the US Dollar ($1.00). The system is fully collateralized by crypto assets (wETH and wBTC) and managed by a core engine contract that governs minting, burning, and liquidations.

## 🚀 Overview

This project consists of two core smart contracts:
1. **`DecentralizedStableCoin.sol`**: The ERC20 token implementation. It inherits from OpenZeppelin.
   
2. **`ARCEngine.sol`** : The brain of the system. It handles collateral deposits, stablecoin minting, collateral withdrawals, token burning, and health-factor-driven liquidations.

### Key Features
* **Exogenous Collateral:** Backed by independent crypto assets (wETH and wBTC).
* **Algorithmic Stability:** Minted and burned dynamically based on collateralization ratios.
* **Over-collateralized:** Users must maintain a strict health factor to avoid liquidation, ensuring the stablecoin is always backed by more than 100% of its value.
* **Gas Optimized:** Built with modern Solidity practices, custom errors, and efficient state management.

---

## 🛠️ Development & Framework

This project is built and tested exclusively using **Foundry**.

### Prerequisites

Ensure you have Foundry installed. If not, run:
```bash
curl -L [https://foundry.paradigm.xyz](https://foundry.paradigm.xyz) | bash
foundryup

