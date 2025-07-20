;; discrete-borrowing-computer
;; 
;; A decentralized, cryptographically secure smart contract for managing 
;; discrete financial borrowing transactions with advanced verification mechanisms.
;; Enables secure, transparent tracking of lending agreements while preserving privacy
;; and ensuring robust computational integrity.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-TRANSACTION-ALREADY-EXISTS (err u201))
(define-constant ERR-BORROWER-NOT-REGISTERED (err u202))
(define-constant ERR-LOAN-ALREADY-REGISTERED (err u203))
(define-constant ERR-LOAN-NOT-REGISTERED (err u204))
(define-constant ERR-INVALID-TRANSACTION (err u205))
(define-constant ERR-PROOF-ALREADY-EXISTS (err u206))

;; Data space definitions

;; Maps borrower identities
(define-map borrower-registry
  principal  ;; borrower
  {
    borrower-id: (string-ascii 64),
    registration-time: uint,
    credit-score: uint
  }
)

;; Stores information about discrete loan transactions
(define-map loan-transactions
  {
    borrower: principal,
    loan-id: (string-ascii 64)
  }
  {
    loan-amount: uint,
    interest-rate: uint,
    loan-term-months: uint,
    registration-time: uint
  }
)

;; Stores cryptographic proofs for loan transactions
(define-map transaction-proofs
  {
    borrower: principal,
    loan-id: (string-ascii 64),
    timestamp: uint
  }
  {
    transaction-hash: (buff 32),     ;; Hash of the transaction details
    verification-proof: (buff 32)    ;; Cryptographic verification hash
  }
)

;; Tracks all loans for a particular borrower
(define-map borrower-loan-registry
  principal  ;; borrower
  (list 100 (string-ascii 64))  ;; list of loan-ids, max 100 loans
)

;; Private functions

;; Checks if the NestNode is registered to the caller
(define-private (is-nest-node-owner (owner principal))
  (is-some (map-get? borrower-registry owner))
)

;; Adds a device to the owner's device list
(define-private (add-device-to-owner-list (owner principal) (device-id (string-ascii 64)))
  (let (
    (current-loan-transactions (default-to (list) (map-get? owner-loan-transactions owner)))
  )
    (map-set owner-loan-transactions owner (append current-loan-transactions device-id))
  )
)

;; Validates if a device is registered to the owner
(define-private (is-device-registered (owner principal) (device-id (string-ascii 64)))
  (is-some (map-get? loan-transactions {owner: owner, device-id: device-id}))
)

;; Public functions

;; Registers a new NestNode system for the homeowner
(define-public (register-nest-node (nest-node-id (string-ascii 64)))
  (let (
    (caller tx-sender)
  )
    (asserts! (is-none (map-get? borrower-registry caller)) ERR-NEST-NODE-ALREADY-REGISTERED)
    
    (map-set borrower-registry caller {
      nest-node-id: nest-node-id,
      registration-time: block-height
    })
    
    (ok true)
  )
)

;; Registers a new IoT device to the homeowner's network
(define-public (register-device 
    (device-id (string-ascii 64))
    (device-name (string-ascii 64))
    (device-type (string-ascii 32)))
  (let (
    (caller tx-sender)
  )
    ;; Check that caller has a registered NestNode
    (asserts! (is-nest-node-owner caller) ERR-NEST-NODE-NOT-REGISTERED)
    ;; Check that device isn't already registered
    (asserts! (not (is-device-registered caller device-id)) ERR-DEVICE-ALREADY-REGISTERED)
    
    ;; Register the device
    (map-set loan-transactions 
      {owner: caller, device-id: device-id}
      {
        device-name: device-name,
        device-type: device-type,
        registration-time: block-height
      }
    )
    
    ;; Add device to owner's device list
    (add-device-to-owner-list caller device-id)
    
    (ok true)
  )
)

;; Records an activity attestation for a device
(define-public (log-device-activity 
    (device-id (string-ascii 64))
    (timestamp uint)
    (action-hash (buff 32))
    (attestation-hash (buff 32)))
  (let (
    (caller tx-sender)
    (log-key {owner: caller, device-id: device-id, timestamp: timestamp})
  )
    ;; Check that caller has a registered NestNode
    (asserts! (is-nest-node-owner caller) ERR-NEST-NODE-NOT-REGISTERED)
    ;; Check that device is registered
    (asserts! (is-device-registered caller device-id) ERR-DEVICE-NOT-REGISTERED)
    ;; Ensure this exact log doesn't already exist
    (asserts! (is-none (map-get? transaction-proofs log-key)) ERR-ATTESTATION-EXISTS)
    
    ;; Store the activity attestation
    (map-set transaction-proofs log-key
      {
        action-hash: action-hash,
        attestation-hash: attestation-hash
      }
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Gets details of a registered NestNode
(define-read-only (get-nest-node-info (owner principal))
  (map-get? borrower-registry owner)
)

;; Gets details of a registered device
(define-read-only (get-device-info (owner principal) (device-id (string-ascii 64)))
  (map-get? loan-transactions {owner: owner, device-id: device-id})
)

;; Gets all loan-transactions registered to an owner
(define-read-only (get-owner-loan-transactions (owner principal))
  (default-to (list) (map-get? owner-loan-transactions owner))
)

;; Retrieves a specific activity log
(define-read-only (get-activity-log (owner principal) (device-id (string-ascii 64)) (timestamp uint))
  (map-get? transaction-proofs {owner: owner, device-id: device-id, timestamp: timestamp})
)

;; Verifies if a provided attestation matches the stored one
(define-read-only (verify-activity-attestation 
    (owner principal)
    (device-id (string-ascii 64))
    (timestamp uint)
    (provided-attestation-hash (buff 32)))
  (let (
    (log-entry (map-get? transaction-proofs {owner: owner, device-id: device-id, timestamp: timestamp}))
  )
    (and
      (is-some log-entry)
      (is-eq provided-attestation-hash (get attestation-hash (unwrap-panic log-entry)))
    )
  )
)

;; Checks if a device was active at a specific time by verifying existence of a log
(define-read-only (was-device-active (owner principal) (device-id (string-ascii 64)) (timestamp uint))
  (is-some (map-get? transaction-proofs {owner: owner, device-id: device-id, timestamp: timestamp}))
)