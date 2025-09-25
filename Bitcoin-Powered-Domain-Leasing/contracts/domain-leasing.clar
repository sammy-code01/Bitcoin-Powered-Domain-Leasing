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
      created-at: stacks-block-height,
      total-leases: u0,
      reputation-score: u100,
      tags: tags
    })
    
    ;; Update user profile
    (let ((profile (default-to 
      { domains-owned: u0, domains-leased: u0, total-earned: u0, total-spent: u0, reputation: u100, joined-at: stacks-block-height }
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
      { domains-owned: u0, domains-leased: u0, total-earned: u0, total-spent: u0, reputation: u100, joined-at: stacks-block-height }
      (map-get? user-profiles caller))))
      (map-set user-profiles caller (merge old-profile { 
        domains-owned: (if (> (get domains-owned old-profile) u0) (- (get domains-owned old-profile) u1) u0) 
      })))
    
    ;; Update new owner profile
    (let ((new-profile (default-to 
      { domains-owned: u0, domains-leased: u0, total-earned: u0, total-spent: u0, reputation: u100, joined-at: stacks-block-height }
      (map-get? user-profiles new-owner))))
      (map-set user-profiles new-owner (merge new-profile { domains-owned: (+ (get domains-owned new-profile) u1) })))
    
    (map-set domain-registry domain-name (merge domain { owner: new-owner }))
    (ok true)))

(define-public (lease-domain 
  (domain-name (string-ascii 64))
  (lease-duration uint)
  (auto-renew bool))
  (let ((caller tx-sender)
        (domain (unwrap! (map-get? domain-registry domain-name) err-not-found)))
    (asserts! (get available-for-lease domain) err-domain-unavailable)
    (asserts! (and (>= lease-duration (get min-lease-duration domain)) 
                   (<= lease-duration (get max-lease-duration domain))) err-invalid-duration)
    (asserts! (is-none (map-get? active-leases domain-name)) err-domain-unavailable)
    
    (let ((total-cost (* (get price-per-block domain) lease-duration))
          (platform-fee-amount (/ (* total-cost platform-fee) u10000))
          (owner-amount (- total-cost platform-fee-amount))
          (domain-owner (get owner domain)))
      (asserts! (>= (stx-get-balance caller) total-cost) err-insufficient-payment)
      
      ;; Transfer payments
      (try! (stx-transfer? owner-amount caller domain-owner))
      (try! (stx-transfer? platform-fee-amount caller contract-owner))
      
      ;; Create lease record
      (map-set active-leases domain-name {
        lessee: caller,
        owner: domain-owner,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height lease-duration),
        total-paid: total-cost,
        price-per-block: (get price-per-block domain),
        auto-renew: auto-renew,
        lease-count: (+ (get total-leases domain) u1)
      })
      
      ;; Update domain stats
      (map-set domain-registry domain-name (merge domain {
        total-leases: (+ (get total-leases domain) u1)
      }))
      
      ;; Update earnings and profiles
      (let ((current-earnings (default-to u0 (map-get? lease-earnings domain-owner))))
        (map-set lease-earnings domain-owner (+ current-earnings owner-amount)))
      
      (update-user-profile-lease caller domain-owner total-cost)
      
      ;; Update platform stats
      (map-set platform-stats "total-leases" 
        (+ u1 (default-to u0 (map-get? platform-stats "total-leases"))))
      
      (ok true))))

(define-public (extend-lease 
  (domain-name (string-ascii 64))
  (additional-duration uint))
  (let ((caller tx-sender)
        (lease (unwrap! (map-get? active-leases domain-name) err-not-found))
        (domain (unwrap! (map-get? domain-registry domain-name) err-not-found)))
    (asserts! (is-eq caller (get lessee lease)) err-unauthorized)
    (asserts! (> (get end-block lease) stacks-block-height) err-lease-expired)
    (asserts! (<= (+ additional-duration (- (get end-block lease) stacks-block-height)) 
                  (get max-lease-duration domain)) err-invalid-duration)
    
    (let ((extension-cost (* (get price-per-block lease) additional-duration))
          (platform-fee-amount (/ (* extension-cost platform-fee) u10000))
          (owner-amount (- extension-cost platform-fee-amount))
          (lease-owner (get owner lease)))
      (asserts! (>= (stx-get-balance caller) extension-cost) err-insufficient-payment)
      
      ;; Transfer payments
      (try! (stx-transfer? owner-amount caller lease-owner))
      (try! (stx-transfer? platform-fee-amount caller contract-owner))
      
      ;; Update lease
      (map-set active-leases domain-name
        (merge lease {
          end-block: (+ (get end-block lease) additional-duration),
          total-paid: (+ (get total-paid lease) extension-cost)
        }))
      
      ;; Update earnings
      (let ((current-earnings (default-to u0 (map-get? lease-earnings lease-owner))))
        (map-set lease-earnings lease-owner (+ current-earnings owner-amount)))
      
      (ok true))))

(define-public (terminate-lease-early (domain-name (string-ascii 64)))
  (let ((caller tx-sender)
        (lease (unwrap! (map-get? active-leases domain-name) err-not-found)))
    (asserts! (is-eq caller (get lessee lease)) err-unauthorized)
    (asserts! (> (get end-block lease) stacks-block-height) err-lease-expired)
    
    ;; Record in history before deletion
    (map-set lease-history { domain: domain-name, lease-id: (get lease-count lease) } {
      lessee: (get lessee lease),
      owner: (get owner lease),
      start-block: (get start-block lease),
      end-block: stacks-block-height,
      amount-paid: (get total-paid lease),
      completed: false
    })
    
    (map-delete active-leases domain-name)
    (ok true)))

(define-public (reclaim-domain (domain-name (string-ascii 64)))
  (let ((caller tx-sender)
        (lease (map-get? active-leases domain-name)))
    (match lease
      lease-data 
      (begin
        (asserts! (<= (get end-block lease-data) stacks-block-height) err-unauthorized)
        
        ;; Record completed lease in history
        (map-set lease-history { domain: domain-name, lease-id: (get lease-count lease-data) } {
          lessee: (get lessee lease-data),
          owner: (get owner lease-data),
          start-block: (get start-block lease-data),
          end-block: (get end-block lease-data),
          amount-paid: (get total-paid lease-data),
          completed: true
        })
        
        (map-delete active-leases domain-name)
        (ok true))
      (ok false))))

(define-public (favorite-domain (domain-name (string-ascii 64)))
  (let ((caller tx-sender))
    (asserts! (is-some (map-get? domain-registry domain-name)) err-not-found)
    (map-set domain-favorites { user: caller, domain: domain-name } true)
    (ok true)))

(define-public (unfavorite-domain (domain-name (string-ascii 64)))
  (let ((caller tx-sender))
    (map-delete domain-favorites { user: caller, domain: domain-name })
    (ok true)))

(define-read-only (get-domain-info (domain-name (string-ascii 64)))
  (map-get? domain-registry domain-name))

(define-read-only (get-lease-info (domain-name (string-ascii 64)))
  (map-get? active-leases domain-name))

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles user))

(define-read-only (get-earnings (owner principal))
  (default-to u0 (map-get? lease-earnings owner)))

(define-read-only (get-lease-history (domain-name (string-ascii 64)) (lease-id uint))
  (map-get? lease-history { domain: domain-name, lease-id: lease-id }))

(define-read-only (is-domain-available (domain-name (string-ascii 64)))
  (let ((domain (map-get? domain-registry domain-name))
        (lease (map-get? active-leases domain-name)))
    (match domain
      domain-data
      (and 
        (get available-for-lease domain-data)
        (is-none lease))
      false)))

(define-read-only (get-platform-stats (stat-name (string-ascii 20)))
  (default-to u0 (map-get? platform-stats stat-name)))

(define-read-only (is-favorite (user principal) (domain-name (string-ascii 64)))
  (default-to false (map-get? domain-favorites { user: user, domain: domain-name })))

(define-read-only (calculate-lease-cost (domain-name (string-ascii 64)) (duration uint))
  (match (map-get? domain-registry domain-name)
    domain-data
    (let ((total (* (get price-per-block domain-data) duration))
          (fee (/ (* total platform-fee) u10000)))
      (ok { total-cost: total, platform-fee: fee, owner-amount: (- total fee) }))
    err-not-found))

(define-read-only (get-domain-reputation (domain-name (string-ascii 64)))
  (match (map-get? domain-registry domain-name)
    domain-data (ok (get reputation-score domain-data))
    err-not-found))

(define-read-only (time-until-lease-expires (domain-name (string-ascii 64)))
  (match (map-get? active-leases domain-name)
    lease-data
    (if (> (get end-block lease-data) stacks-block-height)
      (ok (- (get end-block lease-data) stacks-block-height))
      (ok u0))
    err-not-found))

;; Private helper function
(define-private (update-user-profile-lease (lessee principal) (owner principal) (amount uint))
  (let ((lessee-profile (default-to 
          { domains-owned: u0, domains-leased: u0, total-earned: u0, total-spent: u0, reputation: u100, joined-at: stacks-block-height }
          (map-get? user-profiles lessee)))
        (owner-profile (default-to 
          { domains-owned: u0, domains-leased: u0, total-earned: u0, total-spent: u0, reputation: u100, joined-at: stacks-block-height }
          (map-get? user-profiles owner))))
    
    (map-set user-profiles lessee (merge lessee-profile { 
      domains-leased: (+ (get domains-leased lessee-profile) u1),
      total-spent: (+ (get total-spent lessee-profile) amount)
    }))
    
    (map-set user-profiles owner (merge owner-profile { 
      total-earned: (+ (get total-earned owner-profile) amount)
    }))
    
    true))