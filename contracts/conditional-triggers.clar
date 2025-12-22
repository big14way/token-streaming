;; conditional-triggers.clar
;; Conditional stream release based on external triggers
;; Uses Clarity 4 epoch 3.3

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u11001))
(define-constant ERR_TRIGGER_NOT_MET (err u11002))
(define-constant ERR_STREAM_NOT_FOUND (err u11003))

(define-data-var trigger-counter uint u0)

(define-map stream-triggers
    uint
    {
        stream-id: uint,
        trigger-type: (string-ascii 32),
        condition-value: uint,
        current-value: uint,
        triggered: bool,
        created-at: uint,
        triggered-at: uint
    }
)

(define-map trigger-events
    { trigger-id: uint, event-id: uint }
    {
        event-type: (string-ascii 32),
        value: uint,
        timestamp: uint,
        triggered-release: bool
    }
)

(define-data-var event-counter uint u0)

(define-public (create-trigger
    (stream-id uint)
    (trigger-type (string-ascii 32))
    (condition-value uint))
    (let
        (
            (trigger-id (+ (var-get trigger-counter) u1))
        )
        (map-set stream-triggers trigger-id {
            stream-id: stream-id,
            trigger-type: trigger-type,
            condition-value: condition-value,
            current-value: u0,
            triggered: false,
            created-at: stacks-block-time,
            triggered-at: u0
        })
        (var-set trigger-counter trigger-id)
        (print {
            event: "stream-trigger-created",
            trigger-id: trigger-id,
            stream-id: stream-id,
            trigger-type: trigger-type,
            condition-value: condition-value,
            timestamp: stacks-block-time
        })
        (ok trigger-id)
    )
)

(define-public (update-trigger-value (trigger-id uint) (new-value uint))
    (let
        (
            (trigger (unwrap! (map-get? stream-triggers trigger-id) ERR_STREAM_NOT_FOUND))
            (condition-met (>= new-value (get condition-value trigger)))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set stream-triggers trigger-id
            (merge trigger {
                current-value: new-value,
                triggered: (if condition-met true (get triggered trigger)),
                triggered-at: (if condition-met stacks-block-time (get triggered-at trigger))
            }))
        (if condition-met
            (print {
                event: "trigger-activated",
                trigger-id: trigger-id,
                stream-id: (get stream-id trigger),
                final-value: new-value,
                timestamp: stacks-block-time
            })
            true)
        (ok condition-met)
    )
)

(define-read-only (get-trigger (trigger-id uint))
    (map-get? stream-triggers trigger-id)
)

(define-read-only (is-trigger-met (trigger-id uint))
    (match (map-get? stream-triggers trigger-id)
        trigger (get triggered trigger)
        false)
)
