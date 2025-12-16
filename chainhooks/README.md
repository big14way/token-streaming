# Token Streaming - Chainhooks Integration

Monitor continuous token streaming events in real-time using Hiro Chainhooks.

## Monitored Events

- **Stream Creation**: New payment streams created
- **Claims**: Token withdrawals from streams
- **Cancellations**: Stream cancellations with refunds
- **Balance Updates**: Real-time streaming balance changes

## Setup

```bash
npm install
cp .env.example .env
# Configure your .env file
npm start
```

## Contract Address

- Stream Manager: `${DEPLOYER_ADDRESS}.stream-manager`

See [Chainhooks Documentation](https://docs.hiro.so/chainhooks) for more details.
