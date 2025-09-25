;; Bitcoin-Powered Domain Leasing Platform
;; Advanced rental system for .btc domains with governance and analytics

(define-constant contract-owner tx-sender)
(define-constant platform-fee u50) ;; 0.5% platform fee
(define-constant max-domain-length u64)
(define-constant min-domain-length u3)
(define-constant max-lease-duration u52560) ;; ~1 year in blocks
(define-constant min-lease-duration u144) ;; ~1 day in blocks

;; Error constants
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-domain-unavailable (err u103))
(define-constant err-insufficient-payment (err u104))
(define-constant err-lease-expired (err u105))
(define-constant err-invalid-domain (err u106))
(define-constant err-invalid-duration (err u107))
(define-constant err-domain-exists (err u108))
(define-constant err-insufficient-balance (err u109))
(define-constant err-transfer-failed (err u110))

(define-map domain-registry
  (string-ascii 64)
  {
    owner: principal,
    available-for-lease: bool,
    price-per-block: uint,
    min-lease-duration: uint,
    max-lease-duration: uint,
    created-at: uint,
    total-leases: uint,
    reputation-score: uint,
    tags: (list 5 (string-ascii 20))
  })

(define-map active-leases
  (string-ascii 64)
  {
    lessee: principal,
    owner: principal,
    start-block: uint,
    end-block: uint,
    total-paid: uint,
    price-per-block: uint,
    auto-renew: bool,
    lease-count: uint
  })

(define-map lease-history
  { domain: (string-ascii 64), lease-id: uint }
  {
    lessee: principal,
    owner: principal,
    start-block: uint,
    end-block: uint,
    amount-paid: uint,
    completed: bool
  })

(define-map user-profiles
  principal
  {
    domains-owned: uint,
    domains-leased: uint,
    total-earned: uint,
    total-spent: uint,
    reputation: uint,
    joined-at: uint
  })

(define-map lease-earnings
  principal
  uint)

(define-map platform-stats
  (string-ascii 20)
  uint)

(define-map domain-favorites
  { user: principal, domain: (string-ascii 64) }
  bool)