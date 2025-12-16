import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals, assertExists } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

const ONE_DAY = 86400;
const ONE_MONTH = 2592000;

Clarinet.test({
    name: "Can create a stream",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const sender = accounts.get('wallet_1')!;
        const recipient = accounts.get('wallet_2')!;
        
        const startTime = chain.callReadOnlyFn('stream-manager', 'get-current-time', [], sender.address);
        const start = Number(startTime.result.replace('u', ''));
        
        let block = chain.mineBlock([
            Tx.contractCall('stream-manager', 'create-stream', [
                types.principal(recipient.address),
                types.uint(100000000), // 100 STX
                types.uint(start + 100),
                types.uint(start + 100 + ONE_MONTH)
            ], sender.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Protocol fee is calculated correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        // 0.3% of 100 STX = 0.3 STX = 300000 μSTX
        let fee = chain.callReadOnlyFn(
            'stream-manager',
            'calculate-fee',
            [types.uint(100000000)],
            user.address
        );
        
        assertEquals(fee.result, 'u300000');
    }
});

Clarinet.test({
    name: "End time must be after start time",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const sender = accounts.get('wallet_1')!;
        const recipient = accounts.get('wallet_2')!;
        
        const startTime = chain.callReadOnlyFn('stream-manager', 'get-current-time', [], sender.address);
        const start = Number(startTime.result.replace('u', ''));
        
        let block = chain.mineBlock([
            Tx.contractCall('stream-manager', 'create-stream', [
                types.principal(recipient.address),
                types.uint(100000000),
                types.uint(start + 1000),
                types.uint(start + 500) // End before start - invalid
            ], sender.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(15004); // ERR_INVALID_TIMES
    }
});

Clarinet.test({
    name: "Deposit must be greater than zero",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const sender = accounts.get('wallet_1')!;
        const recipient = accounts.get('wallet_2')!;
        
        const startTime = chain.callReadOnlyFn('stream-manager', 'get-current-time', [], sender.address);
        const start = Number(startTime.result.replace('u', ''));
        
        let block = chain.mineBlock([
            Tx.contractCall('stream-manager', 'create-stream', [
                types.principal(recipient.address),
                types.uint(0), // Invalid amount
                types.uint(start + 100),
                types.uint(start + ONE_MONTH)
            ], sender.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(15005); // ERR_INVALID_AMOUNT
    }
});

Clarinet.test({
    name: "Get protocol stats",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let stats = chain.callReadOnlyFn(
            'stream-manager',
            'get-protocol-stats',
            [],
            user.address
        );
        
        const data = stats.result.expectTuple();
        assertEquals(data['total-streams'], types.uint(0));
        assertEquals(data['paused'], types.bool(false));
    }
});

Clarinet.test({
    name: "Can generate stream message with to-ascii",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const sender = accounts.get('wallet_1')!;
        const recipient = accounts.get('wallet_2')!;
        
        const startTime = chain.callReadOnlyFn('stream-manager', 'get-current-time', [], sender.address);
        const start = Number(startTime.result.replace('u', ''));
        
        // Create stream first
        chain.mineBlock([
            Tx.contractCall('stream-manager', 'create-stream', [
                types.principal(recipient.address),
                types.uint(100000000),
                types.uint(start + 100),
                types.uint(start + ONE_MONTH)
            ], sender.address)
        ]);
        
        let message = chain.callReadOnlyFn(
            'stream-manager',
            'generate-stream-message',
            [types.uint(1)],
            sender.address
        );
        
        assertExists(message.result);
    }
});

Clarinet.test({
    name: "Only recipient can withdraw",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const sender = accounts.get('wallet_1')!;
        const recipient = accounts.get('wallet_2')!;
        const attacker = accounts.get('wallet_3')!;
        
        const startTime = chain.callReadOnlyFn('stream-manager', 'get-current-time', [], sender.address);
        const start = Number(startTime.result.replace('u', ''));
        
        // Create stream
        chain.mineBlock([
            Tx.contractCall('stream-manager', 'create-stream', [
                types.principal(recipient.address),
                types.uint(100000000),
                types.uint(start),
                types.uint(start + ONE_MONTH)
            ], sender.address)
        ]);
        
        // Attacker tries to withdraw
        let block = chain.mineBlock([
            Tx.contractCall('stream-manager', 'withdraw', [
                types.uint(1)
            ], attacker.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(15001); // ERR_NOT_AUTHORIZED
    }
});

Clarinet.test({
    name: "Only sender can cancel stream",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const sender = accounts.get('wallet_1')!;
        const recipient = accounts.get('wallet_2')!;
        
        const startTime = chain.callReadOnlyFn('stream-manager', 'get-current-time', [], sender.address);
        const start = Number(startTime.result.replace('u', ''));
        
        // Create stream
        chain.mineBlock([
            Tx.contractCall('stream-manager', 'create-stream', [
                types.principal(recipient.address),
                types.uint(100000000),
                types.uint(start + 100),
                types.uint(start + ONE_MONTH)
            ], sender.address)
        ]);
        
        // Recipient tries to cancel
        let block = chain.mineBlock([
            Tx.contractCall('stream-manager', 'cancel-stream', [
                types.uint(1)
            ], recipient.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(15001); // ERR_NOT_AUTHORIZED
    }
});

// Stream Factory Tests

Clarinet.test({
    name: "Can create stream template",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const creator = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('stream-factory', 'create-template', [
                types.ascii("Custom Salary"),
                types.uint(0), // TYPE_SALARY
                types.uint(ONE_MONTH * 6), // 6 months
                types.uint(0) // No cliff
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Can calculate salary params",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let params = chain.callReadOnlyFn(
            'stream-factory',
            'calculate-salary-params',
            [
                types.uint(10000000), // 10 STX monthly
                types.uint(12) // 12 months
            ],
            user.address
        );
        
        const data = params.result.expectTuple();
        assertEquals(data['total-amount'], types.uint(120000000)); // 120 STX total
    }
});

Clarinet.test({
    name: "Can calculate vesting params with cliff",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let params = chain.callReadOnlyFn(
            'stream-factory',
            'calculate-vesting-params',
            [
                types.uint(1000000000), // 1000 STX total
                types.uint(48), // 48 months vesting
                types.uint(12) // 12 months cliff
            ],
            user.address
        );
        
        const data = params.result.expectTuple();
        assertEquals(data['total-amount'], types.uint(1000000000));
    }
});

Clarinet.test({
    name: "Cliff cannot exceed duration",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const creator = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('stream-factory', 'create-template', [
                types.ascii("Invalid Template"),
                types.uint(1),
                types.uint(ONE_MONTH), // 1 month duration
                types.uint(ONE_MONTH * 2) // 2 month cliff - invalid
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(15102); // ERR_INVALID_PARAMS
    }
});
