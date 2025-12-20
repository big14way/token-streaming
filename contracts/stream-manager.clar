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
