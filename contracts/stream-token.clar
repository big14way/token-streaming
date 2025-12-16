;; stream-token.clar
;; SIP-010 compliant token for stream protocol testing

;; Uncomment for mainnet/testnet deployment:
;; (impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))

(define-fungible-token stream-token)

(define-data-var token-name (string-ascii 32) "Stream Token")
(define-data-var token-symbol (string-ascii 10) "STRM")
(define-data-var token-decimals uint u6)
(define-data-var token-uri (optional (string-utf8 256)) none)

(define-read-only (get-name)
    (ok (var-get token-name)))

(define-read-only (get-symbol)
    (ok (var-get token-symbol)))

(define-read-only (get-decimals)
    (ok (var-get token-decimals)))

(define-read-only (get-balance (account principal))
    (ok (ft-get-balance stream-token account)))

(define-read-only (get-total-supply)
    (ok (ft-get-supply stream-token)))

(define-read-only (get-token-uri)
    (ok (var-get token-uri)))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) ERR_NOT_AUTHORIZED)
        (try! (ft-transfer? stream-token amount sender recipient))
        (match memo to-print (print to-print) 0x)
        (ok true)))

(define-public (mint (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (ft-mint? stream-token amount recipient)))

(define-public (burn (amount uint))
    (ft-burn? stream-token amount tx-sender))
