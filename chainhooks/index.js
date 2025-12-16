require('dotenv').config();
const { Chainhook } = require('@hirosystems/chainhook-client');

const DEPLOYER_ADDRESS = process.env.DEPLOYER_ADDRESS || 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM';
const STREAM_CONTRACT = `${DEPLOYER_ADDRESS}.stream-manager`;

const chainhook = new Chainhook({
  baseUrl: process.env.CHAINHOOK_NODE_URL || 'http://localhost:20456',
});

async function monitorStreamingEvents() {
  console.log('Monitoring Token Streaming events...');
  console.log('Stream Contract:', STREAM_CONTRACT);

  const streamCreatedHook = {
    uuid: 'stream-created',
    name: 'Stream Created',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'contract_call',
          contract_identifier: STREAM_CONTRACT,
          method: 'create-stream'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/stream-created',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  const withdrawalHook = {
    uuid: 'stream-withdrawal',
    name: 'Stream Withdrawal',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'contract_call',
          contract_identifier: STREAM_CONTRACT,
          method: 'withdraw'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/withdrawal',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  const cancelledHook = {
    uuid: 'stream-cancelled',
    name: 'Stream Cancelled',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'contract_call',
          contract_identifier: STREAM_CONTRACT,
          method: 'cancel-stream'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/cancelled',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  const balanceUpdateHook = {
    uuid: 'stream-balance-update',
    name: 'Stream Balance Update',
    version: 1,
    chains: ['stacks'],
    networks: {
      testnet: {
        'if_this': {
          scope: 'print_event',
          contract_identifier: STREAM_CONTRACT,
          contains: 'Stream'
        },
        'then_that': {
          http_post: {
            url: process.env.WEBHOOK_URL || 'http://localhost:3000/events/balance-update',
            authorization_header: process.env.WEBHOOK_AUTH || 'Bearer secret'
          }
        }
      }
    }
  };

  try {
    await chainhook.createPredicate(streamCreatedHook);
    console.log('Registered: Stream Created hook');

    await chainhook.createPredicate(withdrawalHook);
    console.log('Registered: Withdrawal hook');

    await chainhook.createPredicate(cancelledHook);
    console.log('Registered: Cancelled hook');

    await chainhook.createPredicate(balanceUpdateHook);
    console.log('Registered: Balance Update hook');

    console.log('\nAll hooks registered successfully!');
  } catch (error) {
    console.error('Error registering hooks:', error);
  }
}

function handleEvent(event) {
  console.log('Received event:', JSON.stringify(event, null, 2));
}

monitorStreamingEvents().catch(console.error);

module.exports = { handleEvent };
