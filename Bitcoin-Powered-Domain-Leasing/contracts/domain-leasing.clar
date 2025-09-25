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

(define-public (register-domain 
  (domain-name (string-ascii 64))
  (price-per-block uint)
  (min-duration uint)
  (max-duration uint)
  (tags (list 5 (string-ascii 20))))
  (let ((caller tx-sender)
        (domain-len (len domain-name)))
    (asserts! (and (>= domain-len min-domain-length) (<= domain-len max-domain-length)) err-invalid-domain)
    (asserts! (is-none (map-get? domain-registry domain-name)) err-domain-exists)
    (asserts! (and (>= min-duration min-lease-duration) (<= max-duration max-lease-duration)) err-invalid-duration)
    (asserts! (> price-per-block u0) err-insufficient-payment)
    
    ;; Register domain
    (map-set domain-registry domain-name {
      owner: caller,
      available-for-lease: true,
      price-per-block: price-per-block,
      min-lease-duration: min-duration,
      max-lease-duration: max-duration,
      created-at: block-height,
      total-leases: u0,
      reputation-score: u100,
      tags: tags
    })
    
    ;; Update user profile
    (let ((profile (default-to 
      { domains-owned: u0, domains-leased: u0, total-earned: u0, total-spent: u0, reputation: u100, joined-at: block-height }
      (map-get? user-profiles caller))))
      (map-set user-profiles caller (merge profile { domains-owned: (+ (get domains-owned profile) u1) })))
    
    ;; Update platform stats
    (map-set platform-stats "total-domains" 
      (+ u1 (default-to u0 (map-get? platform-stats "total-domains"))))
    
    (ok true)))

(define-public (update-domain-settings
  (domain-name (string-ascii 64))
  (new-price uint)
  (available bool)
  (new-tags (list 5 (string-ascii 20))))
  (let ((caller tx-sender)
        (domain (unwrap! (map-get? domain-registry domain-name) err-not-found)))
    (asserts! (is-eq caller (get owner domain)) err-unauthorized)
    (asserts! (> new-price u0) err-insufficient-payment)
    
    (map-set domain-registry domain-name (merge domain {
      price-per-block: new-price,
      available-for-lease: available,
      tags: new-tags
    }))
    (ok true)))

(define-public (transfer-domain-ownership
  (domain-name (string-ascii 64))
  (new-owner principal))
  (let ((caller tx-sender)
        (domain (unwrap! (map-get? domain-registry domain-name) err-not-found)))
    (asserts! (is-eq caller (get owner domain)) err-unauthorized)
    (asserts! (is-none (map-get? active-leases domain-name)) err-domain-unavailable)
    
    ;; Update old owner profile
    (let ((old-profile (default-to 
      { domains-owned: u0, domains-leased: u0, total-earned: u0, total-spent: u0, reputation: u100, joined-at: block-height }
      (map-get? user-profiles caller))))
      (map-set user-profiles caller (merge old-profile { 
        domains-owned: (if (> (get domains-owned old-profile) u0) (- (get domains-owned old-profile) u1) u0) 
      })))
    
    ;; Update new owner profile
    (let ((new-profile (default-to 
      { domains-owned: u0, domains-leased: u0, total-earned: u0, total-spent: u0, reputation: u100, joined-at: block-height }
      (map-get? user-profiles new-owner))))
      (map-set user-profiles new-owner (merge new-profile { domains-owned: (+ (get domains-owned new-profile) u1) })))
    
    (map-set domain-registry domain-name (merge domain { owner: new-owner }))
    (ok true)))