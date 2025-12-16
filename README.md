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
