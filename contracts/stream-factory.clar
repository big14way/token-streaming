;; stream-factory.clar
;; Factory for creating common stream types (salary, vesting, subscription)
;; Uses Clarity 4 features: stacks-block-time, to-ascii?

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u15101))
(define-constant ERR_INVALID_PARAMS (err u15102))

;; Time constants
(define-constant ONE_DAY u86400)
(define-constant ONE_WEEK u604800)
(define-constant ONE_MONTH u2592000)
(define-constant ONE_YEAR u31536000)

;; Stream type constants
(define-constant TYPE_SALARY u0)
(define-constant TYPE_VESTING u1)
(define-constant TYPE_SUBSCRIPTION u2)
(define-constant TYPE_GRANT u3)

(define-data-var template-counter uint u0)

;; Stream templates
(define-map templates
    uint
    {
        name: (string-ascii 64),
        stream-type: uint,
        duration: uint,
        cliff-duration: uint,
        creator: principal,
        active: bool
    }
)

;; ========================================
;; Read-Only Functions
;; ========================================

(define-read-only (get-current-time) stacks-block-time)

(define-read-only (get-template (template-id uint))
    (map-get? templates template-id)
)

;; Calculate salary stream params (monthly payment)
(define-read-only (calculate-salary-params (monthly-salary uint) (months uint))
    (let
        (
            (total-amount (* monthly-salary months))
            (duration (* months ONE_MONTH))
            (start-time stacks-block-time)
            (end-time (+ start-time duration))
        )
        {
            total-amount: total-amount,
            duration: duration,
            start-time: start-time,
            end-time: end-time,
            rate-per-second: (/ total-amount duration)
        }
    )
)

;; Calculate vesting params with cliff
(define-read-only (calculate-vesting-params (total-amount uint) (vesting-months uint) (cliff-months uint))
    (let
        (
            (vesting-duration (* vesting-months ONE_MONTH))
            (cliff-duration (* cliff-months ONE_MONTH))
            (start-time stacks-block-time)
            (cliff-end (+ start-time cliff-duration))
            (end-time (+ start-time vesting-duration))
        )
        {
            total-amount: total-amount,
            vesting-duration: vesting-duration,
            cliff-duration: cliff-duration,
            start-time: start-time,
            cliff-end: cliff-end,
            end-time: end-time,
            rate-per-second: (/ total-amount vesting-duration)
        }
    )
)

;; Calculate subscription params
(define-read-only (calculate-subscription-params (monthly-rate uint) (prepaid-months uint))
    (let
        (
            (total-amount (* monthly-rate prepaid-months))
            (duration (* prepaid-months ONE_MONTH))
            (start-time stacks-block-time)
            (end-time (+ start-time duration))
        )
        {
            total-amount: total-amount,
            duration: duration,
            start-time: start-time,
            end-time: end-time,
            monthly-rate: monthly-rate
        }
    )
)

;; Generate template info using to-ascii?
(define-read-only (generate-template-info (template-id uint))
    (match (map-get? templates template-id)
        template (let
            (
                (id-str (unwrap-panic (to-ascii? template-id)))
                (duration-days (/ (get duration template) ONE_DAY))
                (days-str (unwrap-panic (to-ascii? duration-days)))
                (type-str (unwrap-panic (to-ascii? (get stream-type template))))
            )
            (concat 
                (concat (concat "Template #" id-str) (concat ": " (get name template)))
                (concat (concat " | Type: " type-str) (concat " | Duration: " (concat days-str " days")))
            )
        )
        "Template not found"
    )
)

;; Get recommended duration for stream type
(define-read-only (get-recommended-duration (stream-type uint))
    (if (is-eq stream-type TYPE_SALARY)
        ONE_YEAR
        (if (is-eq stream-type TYPE_VESTING)
            (* u4 ONE_YEAR) ;; 4 year vesting
            (if (is-eq stream-type TYPE_SUBSCRIPTION)
                ONE_MONTH
                (* u2 ONE_YEAR) ;; Grant: 2 years
            )
        )
    )
)

;; ========================================
;; Template Management
;; ========================================

;; Create a stream template
(define-public (create-template
    (name (string-ascii 64))
    (stream-type uint)
    (duration uint)
    (cliff-duration uint))
    (let
        (
            (template-id (+ (var-get template-counter) u1))
        )
        (asserts! (> duration u0) ERR_INVALID_PARAMS)
        (asserts! (<= cliff-duration duration) ERR_INVALID_PARAMS)
        (asserts! (<= stream-type u3) ERR_INVALID_PARAMS)
        
        (map-set templates template-id {
            name: name,
            stream-type: stream-type,
            duration: duration,
            cliff-duration: cliff-duration,
            creator: tx-sender,
            active: true
        })
        
        (var-set template-counter template-id)
        (print (generate-template-info template-id))
        
        (ok template-id)
    )
)

;; Deactivate template
(define-public (deactivate-template (template-id uint))
    (let
        (
            (template (unwrap! (map-get? templates template-id) ERR_INVALID_PARAMS))
        )
        (asserts! (or 
            (is-eq tx-sender (get creator template))
            (is-eq tx-sender CONTRACT_OWNER)
        ) ERR_NOT_AUTHORIZED)
        
        (map-set templates template-id (merge template { active: false }))
        (ok true)
    )
)

;; ========================================
;; Preset Templates Initialization
;; ========================================

;; Initialize common templates
(define-public (initialize-presets)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        ;; Monthly Salary (1 year, no cliff)
        (map-set templates u1 {
            name: "Annual Salary",
            stream-type: TYPE_SALARY,
            duration: ONE_YEAR,
            cliff-duration: u0,
            creator: CONTRACT_OWNER,
            active: true
        })
        
        ;; Standard Vesting (4 years, 1 year cliff)
        (map-set templates u2 {
            name: "Standard Vesting",
            stream-type: TYPE_VESTING,
            duration: (* u4 ONE_YEAR),
            cliff-duration: ONE_YEAR,
            creator: CONTRACT_OWNER,
            active: true
        })
        
        ;; Monthly Subscription
        (map-set templates u3 {
            name: "Monthly Subscription",
            stream-type: TYPE_SUBSCRIPTION,
            duration: ONE_MONTH,
            cliff-duration: u0,
            creator: CONTRACT_OWNER,
            active: true
        })
        
        ;; Grant (2 years, 6 month cliff)
        (map-set templates u4 {
            name: "Development Grant",
            stream-type: TYPE_GRANT,
            duration: (* u2 ONE_YEAR),
            cliff-duration: (* u6 ONE_MONTH),
            creator: CONTRACT_OWNER,
            active: true
        })
        
        (var-set template-counter u4)
        
        (ok true)
    )
)
