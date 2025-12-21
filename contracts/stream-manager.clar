;; stream-manager.clar
;; Continuous token streaming protocol for salaries, subscriptions, and vesting
;; Uses Clarity 4 features: stacks-block-time, to-ascii?

;; ========================================
;; Constants
;; ========================================

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u15001))
(define-constant ERR_STREAM_NOT_FOUND (err u15002))
(define-constant ERR_STREAM_DEPLETED (err u15003))
(define-constant ERR_INVALID_TIMES (err u15004))
(define-constant ERR_INVALID_AMOUNT (err u15005))
(define-constant ERR_STREAM_NOT_STARTED (err u15006))
(define-constant ERR_STREAM_CANCELLED (err u15007))
(define-constant ERR_INSUFFICIENT_BALANCE (err u15008))
(define-constant ERR_STREAM_PAUSED (err u15009))
(define-constant ERR_MILESTONE_NOT_FOUND (err u15010))
(define-constant ERR_MILESTONE_CLAIMED (err u15011))
(define-constant ERR_MILESTONE_NOT_REACHED (err u15012))
(define-constant ERR_INVALID_MILESTONE (err u15013))
(define-constant ERR_DELEGATION_EXISTS (err u15014))
(define-constant ERR_DELEGATION_NOT_FOUND (err u15015))
(define-constant ERR_DELEGATION_EXPIRED (err u15016))
(define-constant ERR_SPLIT_NOT_FOUND (err u15017))
(define-constant ERR_INVALID_SPLIT (err u15018))
(define-constant ERR_SPLIT_EXISTS (err u15019))
(define-constant ERR_ESCROW_NOT_FOUND (err u15020))
(define-constant ERR_ESCROW_EXISTS (err u15021))
(define-constant ERR_ESCROW_LOCKED (err u15022))
(define-constant ERR_CONDITION_NOT_MET (err u15023))
(define-constant ERR_INVALID_ORACLE (err u15024))
(define-constant ERR_ESCROW_RELEASED (err u15025))

;; Stream status
(define-constant STATUS_ACTIVE u0)
(define-constant STATUS_COMPLETED u1)
(define-constant STATUS_CANCELLED u2)

;; Protocol fee: 0.3% (30 basis points)
(define-constant PROTOCOL_FEE_BPS u30)

;; ========================================
;; Data Variables
;; ========================================

(define-data-var stream-counter uint u0)
(define-data-var total-streamed uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var protocol-paused bool false)
(define-data-var contract-principal principal tx-sender)

;; ========================================
;; Data Maps
;; ========================================

(define-map streams
    uint
    {
        sender: principal,
        recipient: principal,
        deposit-amount: uint,
        withdrawn-amount: uint,
        start-time: uint,
        end-time: uint,
        rate-per-second: uint,
        status: uint,
        created-at: uint,
        token-contract: (optional principal),
        paused: bool,
        paused-at: (optional uint),
        total-paused-duration: uint
    }
)

;; Track streams by sender
(define-map sender-streams
    principal
    (list 50 uint)
)

;; Track streams by recipient
(define-map recipient-streams
    principal
    (list 50 uint)
)

;; Milestone bonuses
(define-map milestones
    { stream-id: uint, milestone-percentage: uint }
    {
        bonus-amount: uint,
        claimed: bool,
        added-at: uint,
        claimed-at: (optional uint)
    }
)

;; Track milestones per stream
(define-map stream-milestones
    uint
    (list 10 uint)
)

;; ========================================
;; Stream Delegation Data Structures
;; ========================================

;; Delegations for stream withdrawals
(define-map stream-delegations
    { stream-id: uint }
    {
        delegate: principal,
        delegated-at: uint,
        expires-at: uint,
        withdrawal-limit: uint,
        total-withdrawn: uint,
        active: bool
    }
)

;; Stream Splitting System
(define-map stream-splits
    { stream-id: uint }
    {
        recipients: (list 10 principal),
        percentages: (list 10 uint),  ;; In basis points (10000 = 100%)
        active: bool,
        created-at: uint
    }
)

(define-map split-withdrawals
    { stream-id: uint, recipient: principal }
    {
        total-withdrawn: uint,
        last-withdrawal: uint
    }
)

;; ========================================
;; Stream Escrow and Conditional Release
;; ========================================

(define-data-var escrow-counter uint u0)

;; Escrow conditions
(define-constant CONDITION_TIME_BASED u0)
(define-constant CONDITION_MILESTONE_BASED u1)
(define-constant CONDITION_ORACLE_BASED u2)

;; Stream escrows
(define-map stream-escrows
    { stream-id: uint }
    {
        escrow-amount: uint,
        locked-until: uint,
        condition-type: uint,
        condition-met: bool,
        oracle-address: (optional principal),
        oracle-verified: bool,
        release-approved: bool,
        created-at: uint,
        released-at: uint
    }
)

;; Milestone conditions for escrow
(define-map escrow-milestones
    { stream-id: uint, milestone-id: uint }
    {
        description: (string-ascii 256),
        target-date: uint,
        verified: bool,
        verified-by: principal,
        verified-at: uint
    }
)

;; Oracle approvals for escrow release
(define-map oracle-approvals
    { stream-id: uint, oracle: principal }
    {
        approved: bool,
        approval-data: (optional (buff 32)),
        approved-at: uint
    }
)

;; ========================================
;; Traits
;; ========================================

(define-trait ft-trait
    (
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        (get-balance (principal) (response uint uint))
    )
)

;; ========================================
;; Read-Only Functions
;; ========================================

;; Get current timestamp
(define-read-only (get-current-time)
    stacks-block-time
)

;; Get stream details
(define-read-only (get-stream (stream-id uint))
    (map-get? streams stream-id)
)

;; Calculate streamed amount at current time
(define-read-only (get-streamed-amount (stream-id uint))
    (match (map-get? streams stream-id)
        stream (let
            (
                (current-time stacks-block-time)
                (start-time (get start-time stream))
                (end-time (get end-time stream))
                (rate (get rate-per-second stream))
            )
            (if (< current-time start-time)
                u0
                (if (>= current-time end-time)
                    (get deposit-amount stream)
                    (* rate (- current-time start-time))
                )
            )
        )
        u0
    )
)

;; Calculate withdrawable amount (streamed - already withdrawn)
(define-read-only (get-withdrawable-amount (stream-id uint))
    (match (map-get? streams stream-id)
        stream (let
            (
                (streamed (get-streamed-amount stream-id))
                (withdrawn (get withdrawn-amount stream))
            )
            (if (> streamed withdrawn)
                (- streamed withdrawn)
                u0
            )
        )
        u0
    )
)

;; Calculate remaining balance in stream
(define-read-only (get-remaining-balance (stream-id uint))
    (match (map-get? streams stream-id)
        stream (- (get deposit-amount stream) (get-streamed-amount stream-id))
        u0
    )
)

;; Check if stream is active
(define-read-only (is-stream-active (stream-id uint))
    (match (map-get? streams stream-id)
        stream (and 
            (is-eq (get status stream) STATUS_ACTIVE)
            (< stacks-block-time (get end-time stream))
        )
        false
    )
)

;; Get stream progress percentage (0-100)
(define-read-only (get-stream-progress (stream-id uint))
    (match (map-get? streams stream-id)
        stream (let
            (
                (current-time stacks-block-time)
                (start-time (get start-time stream))
                (end-time (get end-time stream))
                (duration (- end-time start-time))
            )
            (if (< current-time start-time)
                u0
                (if (>= current-time end-time)
                    u100
                    (/ (* (- current-time start-time) u100) duration)
                )
            )
        )
        u0
    )
)

;; Generate stream status message using to-ascii?
(define-read-only (generate-stream-message (stream-id uint))
    (match (map-get? streams stream-id)
        stream (let
            (
                (id-str (unwrap-panic (to-ascii? stream-id)))
                (deposit-str (unwrap-panic (to-ascii? (get deposit-amount stream))))
                (withdrawn-str (unwrap-panic (to-ascii? (get withdrawn-amount stream))))
                (progress (get-stream-progress stream-id))
                (progress-str (unwrap-panic (to-ascii? progress)))
            )
            (concat 
                (concat (concat "Stream #" id-str) (concat " | Deposit: " deposit-str))
                (concat (concat " | Withdrawn: " withdrawn-str) (concat " | Progress: " (concat progress-str "%")))
            )
        )
        "Stream not found"
    )
)

;; Generate time remaining message
(define-read-only (get-time-remaining-message (stream-id uint))
    (match (map-get? streams stream-id)
        stream (let
            (
                (current-time stacks-block-time)
                (end-time (get end-time stream))
                (remaining (if (> end-time current-time) (- end-time current-time) u0))
                (days (/ remaining u86400))
                (hours (/ (mod remaining u86400) u3600))
                (days-str (unwrap-panic (to-ascii? days)))
                (hours-str (unwrap-panic (to-ascii? hours)))
            )
            (concat (concat days-str " days, ") (concat hours-str " hours remaining"))
        )
        "Stream not found"
    )
)

;; Calculate protocol fee
(define-read-only (calculate-fee (amount uint))
    (/ (* amount PROTOCOL_FEE_BPS) u10000)
)

;; Get milestone details
(define-read-only (get-milestone (stream-id uint) (milestone-percentage uint))
    (map-get? milestones { stream-id: stream-id, milestone-percentage: milestone-percentage })
)

;; Get all milestones for a stream
(define-read-only (get-stream-milestones (stream-id uint))
    (default-to (list) (map-get? stream-milestones stream-id))
)

;; Check if milestone is claimable
(define-read-only (is-milestone-claimable (stream-id uint) (milestone-percentage uint))
    (match (get-milestone stream-id milestone-percentage)
        milestone (let
            (
                (progress (get-stream-progress stream-id))
            )
            (and
                (not (get claimed milestone))
                (>= progress milestone-percentage)
            )
        )
        false
    )
)

;; Get protocol stats
(define-read-only (get-protocol-stats)
    {
        total-streams: (var-get stream-counter),
        total-streamed: (var-get total-streamed),
        total-fees: (var-get total-fees-collected),
        current-time: stacks-block-time,
        paused: (var-get protocol-paused)
    }
)

;; Get sender's streams
(define-read-only (get-sender-streams (sender principal))
    (default-to (list) (map-get? sender-streams sender))
)

;; Get recipient's streams
(define-read-only (get-recipient-streams (recipient principal))
    (default-to (list) (map-get? recipient-streams recipient))
)

;; ========================================
;; Escrow Read-Only Functions
;; ========================================

(define-read-only (get-stream-escrow (stream-id uint))
    (map-get? stream-escrows { stream-id: stream-id })
)

(define-read-only (get-escrow-milestone (stream-id uint) (milestone-id uint))
    (map-get? escrow-milestones { stream-id: stream-id, milestone-id: milestone-id })
)

(define-read-only (get-oracle-approval (stream-id uint) (oracle principal))
    (map-get? oracle-approvals { stream-id: stream-id, oracle: oracle })
)

(define-read-only (is-escrow-releasable (stream-id uint))
    (match (get-stream-escrow stream-id)
        escrow (let
            (
                (condition-type (get condition-type escrow))
                (current-time stacks-block-time)
            )
            (if (get release-approved escrow)
                true
                (if (is-eq condition-type CONDITION_TIME_BASED)
                    (>= current-time (get locked-until escrow))
                    (get condition-met escrow))))
        false)
)

(define-read-only (get-escrow-status (stream-id uint))
    (match (get-stream-escrow stream-id)
        escrow {
            escrow-amount: (get escrow-amount escrow),
            locked-until: (get locked-until escrow),
            condition-type: (get condition-type escrow),
            condition-met: (get condition-met escrow),
            release-approved: (get release-approved escrow),
            is-releasable: (is-escrow-releasable stream-id),
            released-at: (get released-at escrow)
        }
        {
            escrow-amount: u0,
            locked-until: u0,
            condition-type: u0,
            condition-met: false,
            release-approved: false,
            is-releasable: false,
            released-at: u0
        })
)

;; ========================================
;; Public Functions
;; ========================================

;; Create a new STX stream
(define-public (create-stream
    (recipient principal)
    (deposit-amount uint)
    (start-time uint)
    (end-time uint))
    (let
        (
            (caller tx-sender)
            (stream-id (+ (var-get stream-counter) u1))
            (current-time stacks-block-time)
            (duration (- end-time start-time))
            (fee (calculate-fee deposit-amount))
            (net-deposit (- deposit-amount fee))
            (rate-per-second (/ net-deposit duration))
        )
        ;; Validations
        (asserts! (not (var-get protocol-paused)) ERR_NOT_AUTHORIZED)
        (asserts! (> deposit-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> end-time start-time) ERR_INVALID_TIMES)
        (asserts! (>= start-time current-time) ERR_INVALID_TIMES)
        (asserts! (> duration u0) ERR_INVALID_TIMES)

        ;; Transfer deposit to contract
        (try! (stx-transfer? deposit-amount caller (var-get contract-principal)))

        ;; Transfer fee to protocol
        (try! (stx-transfer? fee (var-get contract-principal) CONTRACT_OWNER))

        ;; Create stream record
        (map-set streams stream-id {
            sender: caller,
            recipient: recipient,
            deposit-amount: net-deposit,
            withdrawn-amount: u0,
            start-time: start-time,
            end-time: end-time,
            rate-per-second: rate-per-second,
            status: STATUS_ACTIVE,
            created-at: current-time,
            token-contract: none,
            paused: false,
            paused-at: none,
            total-paused-duration: u0
        })

        ;; Update sender streams list
        (map-set sender-streams caller
            (unwrap-panic (as-max-len?
                (append (get-sender-streams caller) stream-id)
                u50)))

        ;; Update recipient streams list
        (map-set recipient-streams recipient
            (unwrap-panic (as-max-len?
                (append (get-recipient-streams recipient) stream-id)
                u50)))

        ;; Update counters
        (var-set stream-counter stream-id)
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))

        ;; Print stream info
        (print (generate-stream-message stream-id))

        (ok stream-id)
    )
)

;; Withdraw streamed tokens (recipient only)
(define-public (withdraw (stream-id uint))
    (let
        (
            (caller tx-sender)
            (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
            (withdrawable (get-withdrawable-amount stream-id))
        )
        ;; Validations
        (asserts! (is-eq caller (get recipient stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status stream) STATUS_ACTIVE) ERR_STREAM_CANCELLED)
        (asserts! (> withdrawable u0) ERR_STREAM_DEPLETED)
        
        ;; Transfer to recipient
        (try! (stx-transfer? withdrawable (var-get contract-principal) caller))
        
        ;; Update stream
        (map-set streams stream-id (merge stream {
            withdrawn-amount: (+ (get withdrawn-amount stream) withdrawable)
        }))
        
        ;; Update total streamed
        (var-set total-streamed (+ (var-get total-streamed) withdrawable))
        
        ;; Check if stream is complete
        (if (>= (+ (get withdrawn-amount stream) withdrawable) (get deposit-amount stream))
            (map-set streams stream-id (merge stream {
                withdrawn-amount: (get deposit-amount stream),
                status: STATUS_COMPLETED
            }))
            true
        )
        
        ;; Print withdrawal info
        (print (generate-stream-message stream-id))
        
        (ok withdrawable)
    )
)

;; Withdraw specific amount
(define-public (withdraw-amount (stream-id uint) (amount uint))
    (let
        (
            (caller tx-sender)
            (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
            (withdrawable (get-withdrawable-amount stream-id))
        )
        ;; Validations
        (asserts! (is-eq caller (get recipient stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status stream) STATUS_ACTIVE) ERR_STREAM_CANCELLED)
        (asserts! (<= amount withdrawable) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; Transfer to recipient
        (try! (stx-transfer? amount (var-get contract-principal) caller))
        
        ;; Update stream
        (map-set streams stream-id (merge stream {
            withdrawn-amount: (+ (get withdrawn-amount stream) amount)
        }))
        
        ;; Update total streamed
        (var-set total-streamed (+ (var-get total-streamed) amount))
        
        (ok amount)
    )
)

;; Cancel stream (sender only) - returns unstreamed portion
(define-public (pause-stream (stream-id uint))
    (let ((stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND)))
        (asserts! (is-eq tx-sender (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get paused stream)) ERR_STREAM_PAUSED)
        (asserts! (is-eq (get status stream) STATUS_ACTIVE) ERR_STREAM_CANCELLED)
        (map-set streams stream-id (merge stream {
            paused: true,
            paused-at: (some stacks-block-time)
        }))
        (print { event: "stream-paused", stream-id: stream-id, timestamp: stacks-block-time })
        (ok true)))

(define-public (unpause-stream (stream-id uint))
    (let ((stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
          (paused-duration (match (get paused-at stream)
              pause-time (- stacks-block-time pause-time)
              u0)))
        (asserts! (is-eq tx-sender (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (get paused stream) ERR_NOT_AUTHORIZED)
        (map-set streams stream-id (merge stream {
            paused: false,
            paused-at: none,
            total-paused-duration: (+ (get total-paused-duration stream) paused-duration)
        }))
        (print { event: "stream-unpaused", stream-id: stream-id, paused-duration: paused-duration, timestamp: stacks-block-time })
        (ok true)))

(define-public (cancel-stream (stream-id uint))
    (let
        (
            (caller tx-sender)
            (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
            (streamed (get-streamed-amount stream-id))
            (withdrawn (get withdrawn-amount stream))
            (recipient-owed (- streamed withdrawn))
            (sender-refund (- (get deposit-amount stream) streamed))
        )
        ;; Only sender can cancel
        (asserts! (is-eq caller (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status stream) STATUS_ACTIVE) ERR_STREAM_CANCELLED)
        
        ;; Pay recipient what they're owed
        (if (> recipient-owed u0)
            (try! (stx-transfer? recipient-owed (var-get contract-principal) (get recipient stream)))
            true
        )

        ;; Refund sender unstreamed portion
        (if (> sender-refund u0)
            (try! (stx-transfer? sender-refund (var-get contract-principal) caller))
            true
        )
        
        ;; Mark as cancelled
        (map-set streams stream-id (merge stream {
            withdrawn-amount: streamed,
            status: STATUS_CANCELLED
        }))
        
        ;; Update total streamed
        (var-set total-streamed (+ (var-get total-streamed) recipient-owed))
        
        (ok { recipient-paid: recipient-owed, sender-refunded: sender-refund })
    )
)

;; Top up an existing stream (sender only)
(define-public (top-up-stream (stream-id uint) (additional-amount uint))
    (let
        (
            (caller tx-sender)
            (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
            (fee (calculate-fee additional-amount))
            (net-additional (- additional-amount fee))
            (new-deposit (+ (get deposit-amount stream) net-additional))
            (remaining-time (- (get end-time stream) stacks-block-time))
            (new-rate (/ new-deposit (- (get end-time stream) (get start-time stream))))
        )
        ;; Validations
        (asserts! (is-eq caller (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status stream) STATUS_ACTIVE) ERR_STREAM_CANCELLED)
        (asserts! (> additional-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> remaining-time u0) ERR_STREAM_DEPLETED)
        
        ;; Transfer additional funds
        (try! (stx-transfer? additional-amount caller (var-get contract-principal)))
        (try! (stx-transfer? fee (var-get contract-principal) CONTRACT_OWNER))

        ;; Update stream
        (map-set streams stream-id (merge stream {
            deposit-amount: new-deposit,
            rate-per-second: new-rate
        }))

        ;; Update fees
        (var-set total-fees-collected (+ (var-get total-fees-collected) fee))

        (ok new-deposit)
    )
)

;; Transfer stream to new recipient (recipient only)
(define-public (transfer-stream (stream-id uint) (new-recipient principal))
    (let
        (
            (caller tx-sender)
            (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
        )
        ;; Only current recipient can transfer
        (asserts! (is-eq caller (get recipient stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status stream) STATUS_ACTIVE) ERR_STREAM_CANCELLED)
        
        ;; Update stream recipient
        (map-set streams stream-id (merge stream {
            recipient: new-recipient
        }))
        
        ;; Update recipient streams lists
        (map-set recipient-streams new-recipient
            (unwrap-panic (as-max-len? 
                (append (get-recipient-streams new-recipient) stream-id) 
                u50)))
        
        (ok true)
    )
)

;; ========================================
;; Admin Functions
;; ========================================

;; Pause/unpause protocol
(define-public (set-paused (paused bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set protocol-paused paused)
        (ok true)
    )
)

;; Emergency withdraw (admin only)
(define-public (emergency-withdraw (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (stx-transfer? amount (var-get contract-principal) CONTRACT_OWNER)
    )
)

;; ========================================
;; Milestone Bonus Functions
;; ========================================

;; Add milestone bonus to stream (sender only)
(define-public (add-milestone (stream-id uint) (milestone-percentage uint) (bonus-amount uint))
    (let (
        (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
        (existing-milestones (get-stream-milestones stream-id))
        (current-time stacks-block-time)
        )
        ;; Validations
        (asserts! (is-eq tx-sender (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get status stream) STATUS_ACTIVE) ERR_STREAM_CANCELLED)
        (asserts! (> bonus-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (and (> milestone-percentage u0) (<= milestone-percentage u100)) ERR_INVALID_MILESTONE)
        (asserts! (is-none (get-milestone stream-id milestone-percentage)) ERR_MILESTONE_CLAIMED)

        ;; Transfer bonus to contract
        (try! (stx-transfer? bonus-amount tx-sender (var-get contract-principal)))

        ;; Create milestone
        (map-set milestones
            { stream-id: stream-id, milestone-percentage: milestone-percentage }
            {
                bonus-amount: bonus-amount,
                claimed: false,
                added-at: current-time,
                claimed-at: none
            }
        )

        ;; Add to milestone list
        (map-set stream-milestones stream-id
            (unwrap! (as-max-len? (append existing-milestones milestone-percentage) u10) ERR_INVALID_MILESTONE)
        )

        (print {
            event: "milestone-added",
            stream-id: stream-id,
            milestone-percentage: milestone-percentage,
            bonus-amount: bonus-amount,
            sender: tx-sender,
            timestamp: current-time
        })

        (ok true)
    )
)

;; Claim milestone bonus (recipient only)
(define-public (claim-milestone (stream-id uint) (milestone-percentage uint))
    (let (
        (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
        (milestone (unwrap! (get-milestone stream-id milestone-percentage) ERR_MILESTONE_NOT_FOUND))
        (progress (get-stream-progress stream-id))
        (current-time stacks-block-time)
        )
        ;; Validations
        (asserts! (is-eq tx-sender (get recipient stream)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get claimed milestone)) ERR_MILESTONE_CLAIMED)
        (asserts! (>= progress milestone-percentage) ERR_MILESTONE_NOT_REACHED)

        ;; Mark as claimed
        (map-set milestones
            { stream-id: stream-id, milestone-percentage: milestone-percentage }
            (merge milestone {
                claimed: true,
                claimed-at: (some current-time)
            })
        )

        ;; Transfer bonus to recipient
        (try! (stx-transfer? (get bonus-amount milestone) (var-get contract-principal) tx-sender))

        (print {
            event: "milestone-claimed",
            stream-id: stream-id,
            milestone-percentage: milestone-percentage,
            bonus-amount: (get bonus-amount milestone),
            recipient: tx-sender,
            stream-progress: progress,
            timestamp: current-time
        })

        (ok (get bonus-amount milestone))
    )
)

;; Claim all available milestones (recipient only)
(define-public (claim-all-milestones (stream-id uint))
    (let (
        (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
        (milestone-percentages (get-stream-milestones stream-id))
        )
        ;; Validations
        (asserts! (is-eq tx-sender (get recipient stream)) ERR_NOT_AUTHORIZED)

        ;; Claim all claimable milestones
        (ok (fold claim-single-milestone milestone-percentages u0))
    )
)

;; Helper to claim single milestone in fold
(define-private (claim-single-milestone (milestone-percentage uint) (total-claimed uint))
    (match (claim-milestone (var-get stream-counter) milestone-percentage)
        success (+ total-claimed success)
        error total-claimed
    )
)

;; Remove unclaimed milestone (sender only, before it's claimable)
(define-public (remove-milestone (stream-id uint) (milestone-percentage uint))
    (let (
        (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
        (milestone (unwrap! (get-milestone stream-id milestone-percentage) ERR_MILESTONE_NOT_FOUND))
        (progress (get-stream-progress stream-id))
        )
        ;; Validations
        (asserts! (is-eq tx-sender (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get claimed milestone)) ERR_MILESTONE_CLAIMED)
        (asserts! (< progress milestone-percentage) ERR_MILESTONE_NOT_REACHED)

        ;; Delete milestone
        (map-delete milestones { stream-id: stream-id, milestone-percentage: milestone-percentage })

        ;; Refund bonus to sender
        (try! (stx-transfer? (get bonus-amount milestone) (var-get contract-principal) tx-sender))

        (print {
            event: "milestone-removed",
            stream-id: stream-id,
            milestone-percentage: milestone-percentage,
            bonus-amount: (get bonus-amount milestone),
            sender: tx-sender,
            timestamp: stacks-block-time
        })

        (ok (get bonus-amount milestone))
    )
)

;; ========================================
;; Stream Delegation Functions
;; ========================================

;; Delegate stream to another address
(define-public (delegate-stream (stream-id uint) (delegate principal) (duration uint) (withdrawal-limit uint))
    (let
        (
            (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
            (current-time stacks-block-time)
        )
        (asserts! (is-eq tx-sender (get recipient stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-none (map-get? stream-delegations { stream-id: stream-id })) ERR_DELEGATION_EXISTS)
        (asserts! (> duration u0) ERR_INVALID_TIMES)

        (map-set stream-delegations
            { stream-id: stream-id }
            {
                delegate: delegate,
                delegated-at: current-time,
                expires-at: (+ current-time duration),
                withdrawal-limit: withdrawal-limit,
                total-withdrawn: u0,
                active: true
            }
        )

        (print {
            event: "stream-delegated",
            stream-id: stream-id,
            delegate: delegate,
            duration: duration,
            withdrawal-limit: withdrawal-limit,
            expires-at: (+ current-time duration),
            timestamp: current-time
        })

        (ok true)
    )
)

;; Revoke delegation
(define-public (revoke-delegation (stream-id uint))
    (let
        (
            (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
            (delegation (unwrap! (map-get? stream-delegations { stream-id: stream-id }) ERR_DELEGATION_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender (get recipient stream)) ERR_NOT_AUTHORIZED)

        (map-set stream-delegations
            { stream-id: stream-id }
            (merge delegation { active: false })
        )

        (print {
            event: "delegation-revoked",
            stream-id: stream-id,
            delegate: (get delegate delegation),
            timestamp: stacks-block-time
        })

        (ok true)
    )
)

;; Delegated withdrawal
(define-public (delegated-withdraw (stream-id uint) (amount uint))
    (let
        (
            (stream (unwrap! (map-get? streams stream-id) ERR_STREAM_NOT_FOUND))
            (delegation (unwrap! (map-get? stream-delegations { stream-id: stream-id }) ERR_DELEGATION_NOT_FOUND))
            (current-time stacks-block-time)
            (available (get-withdrawable-amount stream-id))
        )
        (asserts! (is-eq tx-sender (get delegate delegation)) ERR_NOT_AUTHORIZED)
        (asserts! (get active delegation) ERR_DELEGATION_NOT_FOUND)
        (asserts! (< current-time (get expires-at delegation)) ERR_DELEGATION_EXPIRED)
        (asserts! (<= (+ (get total-withdrawn delegation) amount) (get withdrawal-limit delegation)) ERR_INVALID_AMOUNT)
        (asserts! (<= amount available) ERR_INSUFFICIENT_BALANCE)

        ;; Update delegation
        (map-set stream-delegations
            { stream-id: stream-id }
            (merge delegation { total-withdrawn: (+ (get total-withdrawn delegation) amount) })
        )

        ;; Update stream withdrawn
        (map-set streams
            stream-id
            (merge stream { withdrawn-amount: (+ (get withdrawn-amount stream) amount) })
        )

        ;; Transfer to delegate
        (try! (stx-transfer? amount (var-get contract-principal) tx-sender))

        (print {
            event: "delegated-withdrawal",
            stream-id: stream-id,
            delegate: tx-sender,
            amount: amount,
            total-withdrawn-by-delegate: (+ (get total-withdrawn delegation) amount),
            timestamp: current-time
        })

        (ok amount)
    )
)

;; Create stream split
(define-public (create-stream-split (stream-id uint) (recipients (list 10 principal)) (percentages (list 10 uint)))
    (let ((stream (unwrap! (get-stream stream-id) ERR_STREAM_NOT_FOUND))
          (total-pct (fold + percentages u0)))
        (asserts! (is-eq (get sender stream) tx-sender) ERR_NOT_AUTHORIZED)
        (asserts! (is-none (map-get? stream-splits { stream-id: stream-id })) ERR_SPLIT_EXISTS)
        (asserts! (is-eq total-pct u10000) ERR_INVALID_SPLIT)
        (map-set stream-splits { stream-id: stream-id }
            { recipients: recipients, percentages: percentages, active: true, created-at: stacks-block-time })
        (print { event: "stream-split-created", stream-id: stream-id, recipients: recipients, percentages: percentages })
        (ok true)))

;; Withdraw from split stream
(define-public (withdraw-from-split (stream-id uint))
    (let ((stream (unwrap! (get-stream stream-id) ERR_STREAM_NOT_FOUND))
          (split (unwrap! (map-get? stream-splits { stream-id: stream-id }) ERR_SPLIT_NOT_FOUND))
          (available (get-withdrawable-amount stream-id))
          (recipient-idx (unwrap! (index-of (get recipients split) tx-sender) ERR_NOT_AUTHORIZED))
          (pct (unwrap! (element-at (get percentages split) recipient-idx) ERR_INVALID_SPLIT))
          (amount (/ (* available pct) u10000)))
        (asserts! (get active split) ERR_SPLIT_NOT_FOUND)
        (asserts! (> amount u0) ERR_INSUFFICIENT_BALANCE)
        (try! (stx-transfer? amount (var-get contract-principal) tx-sender))
        (map-set streams stream-id (merge stream { withdrawn-amount: (+ (get withdrawn-amount stream) amount) }))
        (map-set split-withdrawals { stream-id: stream-id, recipient: tx-sender }
            { total-withdrawn: (+ (default-to u0 (get total-withdrawn (map-get? split-withdrawals { stream-id: stream-id, recipient: tx-sender }))) amount),
              last-withdrawal: stacks-block-time })
        (print { event: "split-withdrawal", stream-id: stream-id, recipient: tx-sender, amount: amount })
        (ok amount)))

;; ========================================
;; Stream Escrow Public Functions
;; ========================================

;; Create escrow for stream
(define-public (create-stream-escrow (stream-id uint) (escrow-amount uint) (lock-duration uint) (condition-type uint) (oracle-address (optional principal)))
    (let
        (
            (stream (unwrap! (get-stream stream-id) ERR_STREAM_NOT_FOUND))
            (current-time stacks-block-time)
            (locked-until (+ current-time lock-duration))
        )
        (asserts! (is-eq tx-sender (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-none (get-stream-escrow stream-id)) ERR_ESCROW_EXISTS)
        (asserts! (> escrow-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= condition-type CONDITION_ORACLE_BASED) ERR_INVALID_ORACLE)
        
        ;; If oracle-based, verify oracle address is provided
        (asserts! (if (is-eq condition-type CONDITION_ORACLE_BASED)
            (is-some oracle-address)
            true) ERR_INVALID_ORACLE)
        
        ;; Transfer escrow amount to contract
        (try! (stx-transfer? escrow-amount tx-sender (var-get contract-principal)))
        
        ;; Create escrow
        (map-set stream-escrows
            { stream-id: stream-id }
            {
                escrow-amount: escrow-amount,
                locked-until: locked-until,
                condition-type: condition-type,
                condition-met: false,
                oracle-address: oracle-address,
                oracle-verified: false,
                release-approved: false,
                created-at: current-time,
                released-at: u0
            }
        )
        
        (var-set escrow-counter (+ (var-get escrow-counter) u1))
        
        (print {
            event: "escrow-created",
            stream-id: stream-id,
            escrow-amount: escrow-amount,
            locked-until: locked-until,
            condition-type: condition-type,
            oracle-address: oracle-address,
            timestamp: current-time
        })
        
        (ok true)
    )
)

;; Add milestone condition for escrow
(define-public (add-escrow-milestone (stream-id uint) (milestone-id uint) (description (string-ascii 256)) (target-date uint))
    (let
        (
            (escrow (unwrap! (get-stream-escrow stream-id) ERR_ESCROW_NOT_FOUND))
            (stream (unwrap! (get-stream stream-id) ERR_STREAM_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get condition-type escrow) CONDITION_MILESTONE_BASED) ERR_CONDITION_NOT_MET)
        (asserts! (> target-date stacks-block-time) ERR_INVALID_TIMES)
        
        (map-set escrow-milestones
            { stream-id: stream-id, milestone-id: milestone-id }
            {
                description: description,
                target-date: target-date,
                verified: false,
                verified-by: tx-sender,
                verified-at: u0
            }
        )
        
        (print {
            event: "escrow-milestone-added",
            stream-id: stream-id,
            milestone-id: milestone-id,
            description: description,
            target-date: target-date,
            timestamp: stacks-block-time
        })
        
        (ok true)
    )
)

;; Verify milestone completion (sender or admin)
(define-public (verify-escrow-milestone (stream-id uint) (milestone-id uint))
    (let
        (
            (escrow (unwrap! (get-stream-escrow stream-id) ERR_ESCROW_NOT_FOUND))
            (stream (unwrap! (get-stream stream-id) ERR_STREAM_NOT_FOUND))
            (milestone (unwrap! (get-escrow-milestone stream-id milestone-id) ERR_MILESTONE_NOT_FOUND))
        )
        (asserts! (or (is-eq tx-sender (get sender stream)) (is-eq tx-sender CONTRACT_OWNER)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get verified milestone)) ERR_MILESTONE_CLAIMED)
        
        (map-set escrow-milestones
            { stream-id: stream-id, milestone-id: milestone-id }
            (merge milestone {
                verified: true,
                verified-by: tx-sender,
                verified-at: stacks-block-time
            })
        )
        
        ;; Mark condition as met
        (map-set stream-escrows
            { stream-id: stream-id }
            (merge escrow { condition-met: true })
        )
        
        (print {
            event: "escrow-milestone-verified",
            stream-id: stream-id,
            milestone-id: milestone-id,
            verified-by: tx-sender,
            timestamp: stacks-block-time
        })
        
        (ok true)
    )
)

;; Oracle approval for escrow release
(define-public (approve-escrow-release (stream-id uint) (approval-data (optional (buff 32))))
    (let
        (
            (escrow (unwrap! (get-stream-escrow stream-id) ERR_ESCROW_NOT_FOUND))
        )
        (asserts! (is-eq (get condition-type escrow) CONDITION_ORACLE_BASED) ERR_INVALID_ORACLE)
        (asserts! (is-eq (some tx-sender) (get oracle-address escrow)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get oracle-verified escrow)) ERR_ESCROW_RELEASED)
        
        (map-set oracle-approvals
            { stream-id: stream-id, oracle: tx-sender }
            {
                approved: true,
                approval-data: approval-data,
                approved-at: stacks-block-time
            }
        )
        
        ;; Mark escrow as oracle-verified and condition met
        (map-set stream-escrows
            { stream-id: stream-id }
            (merge escrow {
                oracle-verified: true,
                condition-met: true
            })
        )
        
        (print {
            event: "escrow-oracle-approved",
            stream-id: stream-id,
            oracle: tx-sender,
            approval-data: approval-data,
            timestamp: stacks-block-time
        })
        
        (ok true)
    )
)

;; Release escrow funds to stream recipient
(define-public (release-escrow (stream-id uint))
    (let
        (
            (escrow (unwrap! (get-stream-escrow stream-id) ERR_ESCROW_NOT_FOUND))
            (stream (unwrap! (get-stream stream-id) ERR_STREAM_NOT_FOUND))
            (recipient (get recipient stream))
            (escrow-amount (get escrow-amount escrow))
        )
        (asserts! (is-escrow-releasable stream-id) ERR_ESCROW_LOCKED)
        (asserts! (is-eq (get released-at escrow) u0) ERR_ESCROW_RELEASED)
        
        ;; Transfer escrow to recipient
        (try! (stx-transfer? escrow-amount (var-get contract-principal) recipient))
        
        ;; Mark as released
        (map-set stream-escrows
            { stream-id: stream-id }
            (merge escrow {
                release-approved: true,
                released-at: stacks-block-time
            })
        )
        
        (print {
            event: "escrow-released",
            stream-id: stream-id,
            recipient: recipient,
            escrow-amount: escrow-amount,
            timestamp: stacks-block-time
        })
        
        (ok escrow-amount)
    )
)

;; Cancel escrow (sender only, before conditions are met)
(define-public (cancel-escrow (stream-id uint))
    (let
        (
            (escrow (unwrap! (get-stream-escrow stream-id) ERR_ESCROW_NOT_FOUND))
            (stream (unwrap! (get-stream stream-id) ERR_STREAM_NOT_FOUND))
            (refund-amount (get escrow-amount escrow))
        )
        (asserts! (is-eq tx-sender (get sender stream)) ERR_NOT_AUTHORIZED)
        (asserts! (not (get condition-met escrow)) ERR_CONDITION_NOT_MET)
        (asserts! (is-eq (get released-at escrow) u0) ERR_ESCROW_RELEASED)
        
        ;; Refund escrow to sender
        (try! (stx-transfer? refund-amount (var-get contract-principal) tx-sender))
        
        ;; Mark as released (cancelled)
        (map-set stream-escrows
            { stream-id: stream-id }
            (merge escrow {
                release-approved: true,
                released-at: stacks-block-time
            })
        )
        
        (print {
            event: "escrow-cancelled",
            stream-id: stream-id,
            sender: tx-sender,
            refund-amount: refund-amount,
            timestamp: stacks-block-time
        })
        
        (ok refund-amount)
    )
)

