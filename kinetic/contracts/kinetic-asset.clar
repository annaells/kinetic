;; Kinetic Protocol - Decentralized Intellectual Property Management
;; A comprehensive system for minting, trading, and governing creative assets

(define-non-fungible-token synaptic-asset uint)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-ROYALTY (err u101))
(define-constant ERR-ASSET-NOT-FOUND (err u102))
(define-constant ERR-EXPIRED-PROPOSAL (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))
(define-constant ERR-ALREADY-VOTED (err u105))
(define-constant ERR-ASSET-NOT-FOR-SALE (err u106))
(define-constant ERR-INVALID-LICENSE (err u107))
(define-constant ERR-DISPUTE-EXISTS (err u108))

;; Core data variables
(define-data-var last-asset-id uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var platform-fee-percentage uint u5) ;; 5% platform fee
(define-data-var min-stake-amount uint u1000000) ;; 1 STX minimum stake

;; Asset management maps
(define-map asset-metadata-uris uint (string-ascii 256))
(define-map creator-royalty-rates uint uint)
(define-map synaptic-registry uint {
    originator: principal,
    work-title: (string-ascii 64),
    creative-brief: (string-ascii 256),
    creation-timestamp: uint,
    asset-category: (string-ascii 32),
    verification-status: bool
})

;; Licensing system
(define-map asset-licenses uint {
    commercial-allowed: bool,
    derivative-allowed: bool,
    attribution-required: bool,
    license-price: uint,
    license-duration: uint
})

(define-map user-licenses {asset-id: uint, licensee: principal} {
    granted-at: uint,
    expires-at: uint,
    license-type: (string-ascii 32)
})

;; Reputation and verification system
(define-map creator-reputation principal {
    total-sales: uint,
    avg-rating: uint,
    verification-level: uint,
    stake-amount: uint
})

(define-map asset-reviews {asset-id: uint, reviewer: principal} {
    rating: uint,
    review-text: (string-ascii 256),
    timestamp: uint
})

;; Revenue tracking
(define-map creator-earnings principal uint)
(define-map asset-revenue uint uint)
(define-map platform-earnings principal uint)

;; Enhanced governance
(define-map community-proposals uint {
    initiator: principal,
    proposal-name: (string-ascii 64),
    proposal-description: (string-ascii 512),
    voting-deadline: uint,
    affirmative-votes: uint,
    negative-votes: uint,
    minimum-participation: uint,
    executed: bool
})

(define-map proposal-votes {proposal-id: uint, voter: principal} bool)
(define-data-var active-proposals uint u0)

;; Dispute resolution system
(define-map disputes uint {
    plaintiff: principal,
    defendant: principal,
    asset-id: uint,
    dispute-reason: (string-ascii 256),
    status: (string-ascii 16),
    created-at: uint,
    resolved-at: (optional uint)
})
(define-data-var dispute-counter uint u0)

;; Enhanced trading system
(define-map market-offerings uint {
    vendor: principal,
    asking-price: uint,
    available: bool,
    auction-end: (optional uint),
    highest-bidder: (optional principal),
    highest-bid: uint
})

(define-map auction-bids {asset-id: uint, bidder: principal} uint)

;; Collaboration features
(define-map asset-collaborators {asset-id: uint, collaborator: principal} {
    contribution-percentage: uint,
    role: (string-ascii 32),
    approved: bool
})

;; Asset collections
(define-map collections uint {
    creator: principal,
    name: (string-ascii 64),
    description: (string-ascii 256),
    asset-count: uint
})
(define-map asset-to-collection uint uint)
(define-data-var collection-counter uint u0)

;; ================== CORE ASSET FUNCTIONS ==================


;; Asset verification by contract owner or verified validators
(define-public (verify-asset (asset-id uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (let ((asset-data (unwrap! (map-get? synaptic-registry asset-id) ERR-ASSET-NOT-FOUND)))
            (map-set synaptic-registry asset-id (merge asset-data { verification-status: true }))
            (ok true))))

;; Transfer with enhanced ownership tracking
(define-public (relay-ownership (asset-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
        (try! (nft-transfer? synaptic-asset asset-id sender recipient))
        (ok true)))

;; ================== LICENSING SYSTEM ==================

;; Set licensing terms for an asset
(define-public (set-license-terms (asset-id uint)
                                  (commercial bool)
                                  (derivative bool)
                                  (attribution bool)
                                  (price uint)
                                  (duration uint))
    (let ((asset-owner (unwrap! (nft-get-owner? synaptic-asset asset-id) ERR-ASSET-NOT-FOUND)))
        (asserts! (is-eq tx-sender asset-owner) ERR-NOT-AUTHORIZED)
        (map-set asset-licenses asset-id {
            commercial-allowed: commercial,
            derivative-allowed: derivative,
            attribution-required: attribution,
            license-price: price,
            license-duration: duration
        })
        (ok true)))

;; Purchase license for an asset
(define-public (purchase-license (asset-id uint) (license-type (string-ascii 32)))
    (let ((license-terms (unwrap! (map-get? asset-licenses asset-id) ERR-INVALID-LICENSE))
          (asset-owner (unwrap! (nft-get-owner? synaptic-asset asset-id) ERR-ASSET-NOT-FOUND))
          (license-price (get license-price license-terms))
          (duration (get license-duration license-terms)))
        (try! (stx-transfer? license-price tx-sender asset-owner))
        (map-set user-licenses {asset-id: asset-id, licensee: tx-sender} {
            granted-at: block-height,
            expires-at: (+ block-height duration),
            license-type: license-type
        })
        (ok true)))

;; ================== REPUTATION SYSTEM ==================

;; Stake tokens for creator verification
(define-public (stake-for-verification (amount uint))
    (begin
        (asserts! (>= amount (var-get min-stake-amount)) ERR-INSUFFICIENT-FUNDS)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (let ((current-rep (default-to {total-sales: u0, avg-rating: u0, verification-level: u0, stake-amount: u0}
                                      (map-get? creator-reputation tx-sender))))
            (map-set creator-reputation tx-sender 
                (merge current-rep { stake-amount: (+ (get stake-amount current-rep) amount) }))
            (ok true))))

;; Submit review for an asset
(define-public (submit-review (asset-id uint) (rating uint) (review-text (string-ascii 256)))
    (begin
        (asserts! (<= rating u5) (err u1))
        (asserts! (> rating u0) (err u1))
        (map-set asset-reviews {asset-id: asset-id, reviewer: tx-sender} {
            rating: rating,
            review-text: review-text,
            timestamp: block-height
        })
        (ok true)))
