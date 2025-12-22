# Token Streaming Protocol

Continuous, per-second token payments for salaries, subscriptions, vesting, and grants on Stacks.

## Clarity 4 Features Used

| Feature | Usage |
|---------|-------|
| `stacks-block-time` | Real-time stream calculations, withdrawal amounts |
| `restrict-assets?` | Safe token transfers during stream operations |
| `to-ascii?` | Human-readable stream status and time remaining messages |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Stream Factory                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Templates: Salary, Vesting, Subscription, Grant      │   │
│  │  calculate-*-params() → Stream configuration          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Stream Manager                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  create-stream() → Lock tokens, start streaming       │   │
│  │  stacks-block-time → Calculate real-time balances    │   │
│  │  withdraw() → Recipient claims streamed amount        │   │
│  │  cancel-stream() → Refund unstreamed portion         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

1. **Sender creates stream**: Deposits tokens, sets recipient and duration
2. **Tokens stream continuously**: Per-second rate based on deposit/duration
3. **Recipient withdraws**: Claim any streamed amount at any time
4. **Optional cancel**: Sender can cancel, recipient gets streamed portion

## Stream Types

| Type | Use Case | Typical Duration |
|------|----------|------------------|
| Salary | Employee compensation | 1 year |
| Vesting | Token grants with cliff | 4 years |
| Subscription | Service payments | Monthly |
| Grant | Development funding | 2 years |

## Contract Functions

### Create & Manage Streams

```clarity
;; Create a new stream
(create-stream
    (recipient principal)
    (deposit-amount uint)
    (start-time uint)
    (end-time uint))

;; Withdraw streamed tokens (recipient)
(withdraw (stream-id uint))

;; Withdraw specific amount
(withdraw-amount (stream-id uint) (amount uint))

;; Cancel and refund (sender)
(cancel-stream (stream-id uint))

;; Add more tokens to stream
(top-up-stream (stream-id uint) (additional-amount uint))

;; Transfer stream to new recipient
(transfer-stream (stream-id uint) (new-recipient principal))
```

### Read-Only Helpers

```clarity
;; Get withdrawable amount right now
(get-withdrawable-amount (stream-id uint))

;; Get total streamed so far
(get-streamed-amount (stream-id uint))

;; Get remaining balance
(get-remaining-balance (stream-id uint))

;; Get progress percentage (0-100)
(get-stream-progress (stream-id uint))

;; Human-readable status
(generate-stream-message (stream-id uint))
;; Returns: "Stream #1 | Deposit: 100000000 | Withdrawn: 25000000 | Progress: 25%"

;; Time remaining
(get-time-remaining-message (stream-id uint))
;; Returns: "23 days, 5 hours remaining"
```

## Fee Structure

| Fee Type | Rate | Recipient |
|----------|------|-----------|
| Protocol Fee | 0.3% | Protocol treasury |

Fee is deducted from deposit at stream creation.

## Example: Create Salary Stream

```typescript
// Pay employee 10 STX/month for 1 year
const monthlyPay = 10000000; // 10 STX
const months = 12;
const totalDeposit = monthlyPay * months; // 120 STX

const now = await getCurrentTime();
const oneYear = 31536000;

await createStream({
    recipient: employeeAddress,
    depositAmount: totalDeposit,
    startTime: now,
    endTime: now + oneYear
});

// Employee can withdraw anytime
// After 30 days: ~10 STX withdrawable
// After 6 months: ~60 STX withdrawable
// After 12 months: 120 STX withdrawable (minus 0.3% fee)
```

## Example: Vesting with Cliff

```typescript
// 4-year vesting, 1-year cliff
const params = await calculateVestingParams({
    totalAmount: 1000000000, // 1000 STX
    vestingMonths: 48,
    cliffMonths: 12
});

// Cliff: No tokens withdrawable for first year
// After cliff: Linear vesting for remaining 3 years
// Rate: ~20.83 STX/month after cliff
```

## Security Features

1. **Asset Protection**: `restrict-assets?` on all transfers
2. **Time-locked**: Funds release gradually over time
3. **Cancellation Protection**: Recipient always gets earned amount
4. **No Front-running**: Amounts calculated at withdrawal time

## Installation & Testing

```bash
cd token-streaming
clarinet check
clarinet test
```

## Deploy to Testnet

```bash
clarinet deployments generate --testnet
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

## Integration

```typescript
// Monitor stream in frontend
const stream = await getStream(streamId);
const withdrawable = await getWithdrawableAmount(streamId);
const progress = await getStreamProgress(streamId);

// Display to user
console.log(`${progress}% complete`);
console.log(`${withdrawable / 1000000} STX available to withdraw`);
```

## Hiro Chainhooks Integration

Monitor token streaming activity in real-time using Hiro Chainhooks.

### Monitored Events

- Stream creation and configuration
- Token claims/withdrawals from streams
- Stream cancellations with refunds
- Real-time balance updates

### Quick Start

```bash
cd chainhooks
npm install
cp .env.example .env
npm start
```

See `chainhooks/README.md` for detailed documentation.

## License

MIT License

## Testnet Deployment

### conditional-triggers
- **Status**: ✅ Deployed to Testnet
- **Transaction ID**: `ec923b91fdfdcf72fd48e7e3f387e0f5c409b1bb6e0229ed906e17f2711b7eca`
- **Deployer**: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM`
- **Explorer**: https://explorer.hiro.so/txid/ec923b91fdfdcf72fd48e7e3f387e0f5c409b1bb6e0229ed906e17f2711b7eca?chain=testnet
- **Deployment Date**: December 22, 2025

### Network Configuration
- Network: Stacks Testnet
- Clarity Version: 4
- Epoch: 3.3
- Chainhooks: Configured and ready

### Contract Features
- Comprehensive validation and error handling
- Event emission for Chainhook monitoring
- Fully tested with `clarinet check`
- Production-ready security measures

## WalletConnect Integration

This project includes a fully-functional React dApp with WalletConnect v2 integration for seamless interaction with Stacks blockchain wallets.

### Features

- **🔗 Multi-Wallet Support**: Connect with any WalletConnect-compatible Stacks wallet
- **✍️ Transaction Signing**: Sign messages and submit transactions directly from the dApp
- **📝 Contract Interactions**: Call smart contract functions on Stacks testnet
- **🔐 Secure Connection**: End-to-end encrypted communication via WalletConnect relay
- **📱 QR Code Support**: Easy mobile wallet connection via QR code scanning

### Quick Start

#### Prerequisites

- Node.js (v16.x or higher)
- npm or yarn package manager
- A Stacks wallet (Xverse, Leather, or any WalletConnect-compatible wallet)

#### Installation

```bash
cd dapp
npm install
```

#### Running the dApp

```bash
npm start
```

The dApp will open in your browser at `http://localhost:3000`

#### Building for Production

```bash
npm run build
```

### WalletConnect Configuration

The dApp is pre-configured with:

- **Project ID**: 1eebe528ca0ce94a99ceaa2e915058d7
- **Network**: Stacks Testnet (Chain ID: `stacks:2147483648`)
- **Relay**: wss://relay.walletconnect.com
- **Supported Methods**:
  - `stacks_signMessage` - Sign arbitrary messages
  - `stacks_stxTransfer` - Transfer STX tokens
  - `stacks_contractCall` - Call smart contract functions
  - `stacks_contractDeploy` - Deploy new smart contracts

### Project Structure

```
dapp/
├── public/
│   └── index.html
├── src/
│   ├── components/
│   │   ├── WalletConnectButton.js      # Wallet connection UI
│   │   └── ContractInteraction.js       # Contract call interface
│   ├── contexts/
│   │   └── WalletConnectContext.js     # WalletConnect state management
│   ├── hooks/                            # Custom React hooks
│   ├── utils/                            # Utility functions
│   ├── config/
│   │   └── stacksConfig.js             # Network and contract configuration
│   ├── styles/                          # CSS styling
│   ├── App.js                           # Main application component
│   └── index.js                         # Application entry point
└── package.json
```

### Usage Guide

#### 1. Connect Your Wallet

Click the "Connect Wallet" button in the header. A QR code will appear - scan it with your mobile Stacks wallet or use the desktop wallet extension.

#### 2. Interact with Contracts

Once connected, you can:

- View your connected address
- Call read-only contract functions
- Submit contract call transactions
- Sign messages for authentication

#### 3. Disconnect

Click the "Disconnect" button to end the WalletConnect session.

### Customization

#### Updating Contract Configuration

Edit `src/config/stacksConfig.js` to point to your deployed contracts:

```javascript
export const CONTRACT_CONFIG = {
  contractName: 'your-contract-name',
  contractAddress: 'YOUR_CONTRACT_ADDRESS',
  network: 'testnet' // or 'mainnet'
};
```

#### Adding Custom Contract Functions

Modify `src/components/ContractInteraction.js` to add your contract-specific functions:

```javascript
const myCustomFunction = async () => {
  const result = await callContract(
    CONTRACT_CONFIG.contractAddress,
    CONTRACT_CONFIG.contractName,
    'your-function-name',
    [functionArgs]
  );
};
```

### Technical Details

#### WalletConnect v2 Implementation

The dApp uses the official WalletConnect v2 Sign Client with:

- **@walletconnect/sign-client**: Core WalletConnect functionality
- **@walletconnect/utils**: Helper utilities for encoding/decoding
- **@walletconnect/qrcode-modal**: QR code display for mobile connection
- **@stacks/connect**: Stacks-specific wallet integration
- **@stacks/transactions**: Transaction building and signing
- **@stacks/network**: Network configuration for testnet/mainnet

#### BigInt Serialization

The dApp includes BigInt serialization support for handling large numbers in Clarity contracts:

```javascript
BigInt.prototype.toJSON = function() { return this.toString(); };
```

### Supported Wallets

Any wallet supporting WalletConnect v2 and Stacks blockchain, including:

- **Xverse Wallet** (Recommended)
- **Leather Wallet** (formerly Hiro Wallet)
- **Boom Wallet**
- Any other WalletConnect-compatible Stacks wallet

### Troubleshooting

**Connection Issues:**
- Ensure your wallet app supports WalletConnect v2
- Check that you're on the correct network (testnet vs mainnet)
- Try refreshing the QR code or restarting the dApp

**Transaction Failures:**
- Verify you have sufficient STX for gas fees
- Confirm the contract address and function names are correct
- Check that post-conditions are properly configured

**Build Errors:**
- Clear node_modules and reinstall: `rm -rf node_modules && npm install`
- Ensure Node.js version is 16.x or higher
- Check for dependency conflicts in package.json

### Resources

- [WalletConnect Documentation](https://docs.walletconnect.com/)
- [Stacks.js Documentation](https://docs.stacks.co/build-apps/stacks.js)
- [Xverse WalletConnect Guide](https://docs.xverse.app/wallet-connect)
- [Stacks Blockchain Documentation](https://docs.stacks.co/)

### Security Considerations

- Never commit your private keys or seed phrases
- Always verify transaction details before signing
- Use testnet for development and testing
- Audit smart contracts before mainnet deployment
- Keep dependencies updated for security patches

### License

This dApp implementation is provided as-is for integration with the Stacks smart contracts in this repository.

