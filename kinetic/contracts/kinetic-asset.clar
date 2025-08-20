;; Synaptic Protocol - Decentralized Intellectual Property Management
;; A comprehensive system for minting, trading, and governing creative assets

(define-non-fungible-token synaptic-asset uint)

(define-data-var last-asset-id uint u0)
(define-map asset-metadata-uris uint (string-ascii 256))
(define-map creator-royalty-rates uint uint)
(define-map synaptic-registry uint {
    originator: principal,
    work-title: (string-ascii 64),
    creative-brief: (string-ascii 256)
})

;; Mint new synaptic asset
(define-public (forge-asset (metadata-uri (string-ascii 256))
                           (work-title (string-ascii 64))
                           (creative-brief (string-ascii 256))
                           (royalty-percentage uint))
    (let ((asset-id (+ (var-get last-asset-id) u1)))
        (asserts! (<= royalty-percentage u100) (err u1))
        (try! (nft-mint? synaptic-asset asset-id tx-sender))
        (map-set asset-metadata-uris asset-id metadata-uri)
        (map-set creator-royalty-rates asset-id royalty-percentage)
        (map-set synaptic-registry asset-id {
            originator: tx-sender,
            work-title: work-title,
            creative-brief: creative-brief
        })
        (var-set last-asset-id asset-id)
        (ok asset-id)))

;; Transfer synaptic asset
(define-public (relay-ownership (asset-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) (err u2))
        (try! (nft-transfer? synaptic-asset asset-id sender recipient))
        (ok true)))

;; Retrieve asset registry data
(define-read-only (get-asset-registry (asset-id uint))
    (ok (map-get? synaptic-registry asset-id)))

;; Revenue Distribution Engine
(define-map creator-earnings principal uint)

;; Process and distribute creator earnings
(define-public (distribute-earnings (asset-id uint) (gross-amount uint))
    (let ((royalty-rate (default-to u0 (map-get? creator-royalty-rates asset-id)))
          (registry-data (unwrap! (map-get? synaptic-registry asset-id) (err u1)))
          (originator (get originator registry-data))
          (creator-share (/ (* gross-amount royalty-rate) u100)))
        (try! (stx-transfer? creator-share tx-sender originator))
        (ok true)))

;; Governance Framework
(define-map community-proposals uint {
    initiator: principal,
    proposal-name: (string-ascii 64),
    voting-deadline: uint,
    affirmative-votes: uint,
    negative-votes: uint
})
(define-data-var active-proposals uint u0)

;; Initialize community proposal
(define-public (initiate-proposal (proposal-name (string-ascii 64)) (voting-duration uint))
    (let ((proposal-id (+ (var-get active-proposals) u1)))
        (map-set community-proposals proposal-id {
            initiator: tx-sender,
            proposal-name: proposal-name,
            voting-deadline: (+ block-height voting-duration),
            affirmative-votes: u0,
            negative-votes: u0
        })
        (var-set active-proposals proposal-id)
        (ok proposal-id)))

;; Cast vote on community proposal
(define-public (cast-vote (proposal-id uint) (affirmative bool))
    (let ((proposal-data (unwrap! (map-get? community-proposals proposal-id) (err u1))))
        (asserts! (< block-height (get voting-deadline proposal-data)) (err u2))
        (if affirmative
            (map-set community-proposals proposal-id
                (merge proposal-data { affirmative-votes: (+ (get affirmative-votes proposal-data) u1) }))
            (map-set community-proposals proposal-id
                (merge proposal-data { negative-votes: (+ (get negative-votes proposal-data) u1) })))
        (ok true)))

;; Trading Exchange
(define-map market-offerings uint {
    vendor: principal,
    asking-price: uint,
    available: bool
})

;; Post asset for sale
(define-public (post-offering (asset-id uint) (asking-price uint))
    (let ((current-owner (unwrap! (nft-get-owner? synaptic-asset asset-id) (err u1))))
        (asserts! (is-eq tx-sender current-owner) (err u2))
        (map-set market-offerings asset-id {
            vendor: tx-sender,
            asking-price: asking-price,
            available: true
        })
        (ok true)))

;; Execute asset purchase
(define-public (execute-purchase (asset-id uint))
    (let ((offering-data (unwrap! (map-get? market-offerings asset-id) (err u1))))
        (asserts! (get available offering-data) (err u2))
        (try! (stx-transfer? (get asking-price offering-data) tx-sender (get vendor offering-data)))
        (try! (relay-ownership asset-id (get vendor offering-data) tx-sender))
        (map-set market-offerings asset-id (merge offering-data { available: false }))
        (try! (distribute-earnings asset-id (get asking-price offering-data)))
        (ok true)))