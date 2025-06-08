(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_MEMBER (err u101))
(define-constant ERR_NOT_MEMBER (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_SESSION_NOT_FOUND (err u105))
(define-constant ERR_SESSION_ALREADY_COMPLETED (err u106))
(define-constant ERR_CANNOT_RATE_OWN_SESSION (err u107))
(define-constant ERR_INVALID_RATING (err u108))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u109))
(define-constant ERR_ALREADY_VOTED (err u110))
(define-constant ERR_VOTING_ENDED (err u111))

(define-data-var next-member-id uint u1)
(define-data-var next-session-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var total-members uint u0)
(define-data-var dao-treasury uint u0)

(define-map members
  { member-id: uint }
  {
    address: principal,
    reputation: uint,
    sessions-completed: uint,
    total-rating: uint,
    rating-count: uint,
    joined-at: uint,
    is-active: bool
  }
)

(define-map member-addresses
  { address: principal }
  { member-id: uint }
)

(define-map support-sessions
  { session-id: uint }
  {
    supporter: principal,
    seeker: principal,
    topic: (string-ascii 100),
    duration: uint,
    reward: uint,
    status: (string-ascii 20),
    created-at: uint,
    completed-at: (optional uint)
  }
)

(define-map session-ratings
  { session-id: uint, rater: principal }
  { rating: uint, feedback: (string-ascii 200) }
)

(define-map proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    reward-amount: uint,
    votes-for: uint,
    votes-against: uint,
    voting-ends: uint,
    executed: bool
  }
)

(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  { vote: bool }
)

(define-public (join-dao)
  (let
    (
      (caller tx-sender)
      (member-id (var-get next-member-id))
    )
    (asserts! (is-none (map-get? member-addresses { address: caller })) ERR_ALREADY_MEMBER)
    (map-set members
      { member-id: member-id }
      {
        address: caller,
        reputation: u10,
        sessions-completed: u0,
        total-rating: u0,
        rating-count: u0,
        joined-at: stacks-block-height,
        is-active: true
      }
    )
    (map-set member-addresses { address: caller } { member-id: member-id })
    (var-set next-member-id (+ member-id u1))
    (var-set total-members (+ (var-get total-members) u1))
    (ok member-id)
  )
)

(define-public (create-support-session (seeker principal) (topic (string-ascii 100)) (duration uint) (reward uint))
  (let
    (
      (session-id (var-get next-session-id))
      (supporter tx-sender)
    )
    (asserts! (is-some (map-get? member-addresses { address: supporter })) ERR_NOT_MEMBER)
    (asserts! (is-some (map-get? member-addresses { address: seeker })) ERR_NOT_MEMBER)
    (asserts! (> reward u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? reward supporter (as-contract tx-sender)))
    (map-set support-sessions
      { session-id: session-id }
      {
        supporter: supporter,
        seeker: seeker,
        topic: topic,
        duration: duration,
        reward: reward,
        status: "active",
        created-at: stacks-block-height,
        completed-at: none
      }
    )
    (var-set next-session-id (+ session-id u1))
    (var-set dao-treasury (+ (var-get dao-treasury) reward))
    (ok session-id)
  )
)

(define-public (complete-session (session-id uint))
  (let
    (
      (session (unwrap! (map-get? support-sessions { session-id: session-id }) ERR_SESSION_NOT_FOUND))
      (supporter (get supporter session))
      (seeker (get seeker session))
    )
    (asserts! (or (is-eq tx-sender supporter) (is-eq tx-sender seeker)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status session) "active") ERR_SESSION_ALREADY_COMPLETED)
    (map-set support-sessions
      { session-id: session-id }
      (merge session { status: "completed", completed-at: (some stacks-block-height) })
    )
    (try! (as-contract (stx-transfer? (get reward session) tx-sender supporter)))
    (var-set dao-treasury (- (var-get dao-treasury) (get reward session)))
    (update-member-stats supporter)
    (ok true)
  )
)

(define-public (rate-session (session-id uint) (rating uint) (feedback (string-ascii 200)))
  (let
    (
      (session (unwrap! (map-get? support-sessions { session-id: session-id }) ERR_SESSION_NOT_FOUND))
      (supporter (get supporter session))
      (rater tx-sender)
    )
    (asserts! (not (is-eq rater supporter)) ERR_CANNOT_RATE_OWN_SESSION)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_RATING)
    (asserts! (is-eq (get status session) "completed") ERR_SESSION_NOT_FOUND)
    (asserts! (is-none (map-get? session-ratings { session-id: session-id, rater: rater })) ERR_ALREADY_VOTED)
    (map-set session-ratings
      { session-id: session-id, rater: rater }
      { rating: rating, feedback: feedback }
    )
    (update-supporter-rating supporter rating)
    (ok true)
  )
)

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (reward-amount uint))
  (let
    (
      (proposal-id (var-get next-proposal-id))
      (proposer tx-sender)
    )
    (asserts! (is-some (map-get? member-addresses { address: proposer })) ERR_NOT_MEMBER)
    (map-set proposals
      { proposal-id: proposal-id }
      {
        proposer: proposer,
        title: title,
        description: description,
        reward-amount: reward-amount,
        votes-for: u0,
        votes-against: u0,
        voting-ends: (+ stacks-block-height u144),
        executed: false
      }
    )
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

(define-public (vote-proposal (proposal-id uint) (vote bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
      (voter tx-sender)
    )
    (asserts! (is-some (map-get? member-addresses { address: voter })) ERR_NOT_MEMBER)
    (asserts! (< stacks-block-height (get voting-ends proposal)) ERR_VOTING_ENDED)
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })) ERR_ALREADY_VOTED)
    (map-set proposal-votes { proposal-id: proposal-id, voter: voter } { vote: vote })
    (if vote
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-for: (+ (get votes-for proposal) u1) })
      )
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-against: (+ (get votes-against proposal) u1) })
      )
    )
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
    )
    (asserts! (>= stacks-block-height (get voting-ends proposal)) ERR_VOTING_ENDED)
    (asserts! (not (get executed proposal)) ERR_ALREADY_VOTED)
    (asserts! (> (get votes-for proposal) (get votes-against proposal)) ERR_NOT_AUTHORIZED)
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal { executed: true })
    )
    (if (> (get reward-amount proposal) u0)
      (try! (as-contract (stx-transfer? (get reward-amount proposal) tx-sender (get proposer proposal))))
      true
    )
    (ok true)
  )
)

(define-read-only (get-member (member-id uint))
  (map-get? members { member-id: member-id })
)

(define-read-only (get-member-by-address (address principal))
  (match (map-get? member-addresses { address: address })
    member-data (map-get? members { member-id: (get member-id member-data) })
    none
  )
)

(define-read-only (get-session (session-id uint))
  (map-get? support-sessions { session-id: session-id })
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-dao-stats)
  {
    total-members: (var-get total-members),
    treasury: (var-get dao-treasury),
    total-sessions: (- (var-get next-session-id) u1),
    total-proposals: (- (var-get next-proposal-id) u1)
  }
)

(define-read-only (get-session-rating (session-id uint) (rater principal))
  (map-get? session-ratings { session-id: session-id, rater: rater })
)

(define-private (update-member-stats (member-address principal))
  (match (map-get? member-addresses { address: member-address })
    member-data
      (match (map-get? members { member-id: (get member-id member-data) })
        member-info
          (map-set members
            { member-id: (get member-id member-data) }
            (merge member-info {
              sessions-completed: (+ (get sessions-completed member-info) u1),
              reputation: (+ (get reputation member-info) u5)
            })
          )
        false
      )
    false
  )
)

(define-private (update-supporter-rating (supporter principal) (rating uint))
  (match (map-get? member-addresses { address: supporter })
    member-data
      (match (map-get? members { member-id: (get member-id member-data) })
        member-info
          (map-set members
            { member-id: (get member-id member-data) }
            (merge member-info {
              total-rating: (+ (get total-rating member-info) rating),
              rating-count: (+ (get rating-count member-info) u1)
            })
          )
        false
      )
    false
  )
)