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
(define-constant ERR_CIRCLE_NOT_FOUND (err u112))
(define-constant ERR_CIRCLE_FULL (err u113))
(define-constant ERR_NOT_CIRCLE_MEMBER (err u114))
(define-constant ERR_ALREADY_CIRCLE_MEMBER (err u115))
(define-constant ERR_CIRCLE_INACTIVE (err u116))
(define-constant ERR_MILESTONE_NOT_FOUND (err u117))
(define-constant ERR_MILESTONE_ALREADY_COMPLETED (err u118))
(define-constant ERR_INSUFFICIENT_CIRCLE_MEMBERS (err u119))

(define-data-var next-member-id uint u1)
(define-data-var next-session-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var next-circle-id uint u1)
(define-data-var next-milestone-id uint u1)
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

(define-map learning-circles
  { circle-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 300),
    creator: principal,
    max-members: uint,
    current-members: uint,
    skill-focus: (string-ascii 50),
    reward-pool: uint,
    is-active: bool,
    created-at: uint,
    milestones-completed: uint,
    total-milestones: uint
  }
)

(define-map circle-members
  { circle-id: uint, member: principal }
  {
    joined-at: uint,
    contribution-score: uint,
    milestones-completed: uint,
    is-active: bool
  }
)

(define-map circle-milestones
  { milestone-id: uint }
  {
    circle-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 250),
    reward-amount: uint,
    required-completions: uint,
    current-completions: uint,
    is-completed: bool,
    created-at: uint,
    completed-at: (optional uint)
  }
)

(define-map milestone-completions
  { milestone-id: uint, member: principal }
  {
    completed-at: uint,
    proof: (string-ascii 200)
  }
)

(define-map circle-membership-count
  { member: principal }
  { active-circles: uint }
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

(define-public (create-learning-circle (name (string-ascii 100)) (description (string-ascii 300)) (skill-focus (string-ascii 50)) (max-members uint) (reward-pool uint))
  (let
    (
      (circle-id (var-get next-circle-id))
      (creator tx-sender)
    )
    (asserts! (is-some (map-get? member-addresses { address: creator })) ERR_NOT_MEMBER)
    (asserts! (> max-members u1) ERR_INVALID_AMOUNT)
    (asserts! (> reward-pool u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? reward-pool creator (as-contract tx-sender)))
    (map-set learning-circles
      { circle-id: circle-id }
      {
        name: name,
        description: description,
        creator: creator,
        max-members: max-members,
        current-members: u1,
        skill-focus: skill-focus,
        reward-pool: reward-pool,
        is-active: true,
        created-at: stacks-block-height,
        milestones-completed: u0,
        total-milestones: u0
      }
    )
    (map-set circle-members
      { circle-id: circle-id, member: creator }
      {
        joined-at: stacks-block-height,
        contribution-score: u0,
        milestones-completed: u0,
        is-active: true
      }
    )
    (update-member-circle-count creator true)
    (var-set next-circle-id (+ circle-id u1))
    (var-set dao-treasury (+ (var-get dao-treasury) reward-pool))
    (ok circle-id)
  )
)

(define-public (join-learning-circle (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? learning-circles { circle-id: circle-id }) ERR_CIRCLE_NOT_FOUND))
      (member tx-sender)
    )
    (asserts! (is-some (map-get? member-addresses { address: member })) ERR_NOT_MEMBER)
    (asserts! (get is-active circle) ERR_CIRCLE_INACTIVE)
    (asserts! (< (get current-members circle) (get max-members circle)) ERR_CIRCLE_FULL)
    (asserts! (is-none (map-get? circle-members { circle-id: circle-id, member: member })) ERR_ALREADY_CIRCLE_MEMBER)
    (map-set circle-members
      { circle-id: circle-id, member: member }
      {
        joined-at: stacks-block-height,
        contribution-score: u0,
        milestones-completed: u0,
        is-active: true
      }
    )
    (map-set learning-circles
      { circle-id: circle-id }
      (merge circle { current-members: (+ (get current-members circle) u1) })
    )
    (update-member-circle-count member true)
    (ok true)
  )
)

(define-public (leave-learning-circle (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? learning-circles { circle-id: circle-id }) ERR_CIRCLE_NOT_FOUND))
      (member tx-sender)
      (member-data (unwrap! (map-get? circle-members { circle-id: circle-id, member: member }) ERR_NOT_CIRCLE_MEMBER))
    )
    (map-set circle-members
      { circle-id: circle-id, member: member }
      (merge member-data { is-active: false })
    )
    (map-set learning-circles
      { circle-id: circle-id }
      (merge circle { current-members: (- (get current-members circle) u1) })
    )
    (update-member-circle-count member false)
    (ok true)
  )
)

(define-public (create-circle-milestone (circle-id uint) (title (string-ascii 100)) (description (string-ascii 250)) (reward-amount uint) (required-completions uint))
  (let
    (
      (milestone-id (var-get next-milestone-id))
      (circle (unwrap! (map-get? learning-circles { circle-id: circle-id }) ERR_CIRCLE_NOT_FOUND))
      (creator tx-sender)
    )
    (asserts! (is-eq creator (get creator circle)) ERR_NOT_AUTHORIZED)
    (asserts! (> required-completions u0) ERR_INVALID_AMOUNT)
    (asserts! (<= required-completions (get current-members circle)) ERR_INSUFFICIENT_CIRCLE_MEMBERS)
    (map-set circle-milestones
      { milestone-id: milestone-id }
      {
        circle-id: circle-id,
        title: title,
        description: description,
        reward-amount: reward-amount,
        required-completions: required-completions,
        current-completions: u0,
        is-completed: false,
        created-at: stacks-block-height,
        completed-at: none
      }
    )
    (map-set learning-circles
      { circle-id: circle-id }
      (merge circle { total-milestones: (+ (get total-milestones circle) u1) })
    )
    (var-set next-milestone-id (+ milestone-id u1))
    (ok milestone-id)
  )
)

(define-public (complete-milestone (milestone-id uint) (proof (string-ascii 200)))
  (let
    (
      (milestone (unwrap! (map-get? circle-milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
      (member tx-sender)
      (circle-id (get circle-id milestone))
    )
    (asserts! (is-some (map-get? circle-members { circle-id: circle-id, member: member })) ERR_NOT_CIRCLE_MEMBER)
    (asserts! (not (get is-completed milestone)) ERR_MILESTONE_ALREADY_COMPLETED)
    (asserts! (is-none (map-get? milestone-completions { milestone-id: milestone-id, member: member })) ERR_ALREADY_VOTED)
    (map-set milestone-completions
      { milestone-id: milestone-id, member: member }
      {
        completed-at: stacks-block-height,
        proof: proof
      }
    )
    (let
      (
        (updated-completions (+ (get current-completions milestone) u1))
        (updated-milestone (merge milestone { current-completions: updated-completions }))
      )
      (map-set circle-milestones
        { milestone-id: milestone-id }
        updated-milestone
      )
      (update-member-contribution member circle-id)
      (if (>= updated-completions (get required-completions milestone))
        (complete-circle-milestone milestone-id)
        (ok true)
      )
    )
  )
)

(define-public (distribute-circle-rewards (circle-id uint))
  (let
    (
      (circle (unwrap! (map-get? learning-circles { circle-id: circle-id }) ERR_CIRCLE_NOT_FOUND))
      (distributor tx-sender)
    )
    (asserts! (is-eq distributor (get creator circle)) ERR_NOT_AUTHORIZED)
    (asserts! (> (get milestones-completed circle) u0) ERR_MILESTONE_NOT_FOUND)
    (asserts! (>= (get reward-pool circle) u1000) ERR_INSUFFICIENT_FUNDS)
    (let
      (
        (reward-per-milestone (/ (get reward-pool circle) (get milestones-completed circle)))
        (total-reward (* reward-per-milestone (get current-members circle)))
      )
      (try! (as-contract (stx-transfer? total-reward tx-sender distributor)))
      (map-set learning-circles
        { circle-id: circle-id }
        (merge circle { reward-pool: (- (get reward-pool circle) total-reward) })
      )
      (var-set dao-treasury (- (var-get dao-treasury) total-reward))
      (ok total-reward)
    )
  )
)

(define-read-only (get-learning-circle (circle-id uint))
  (map-get? learning-circles { circle-id: circle-id })
)

(define-read-only (get-circle-member (circle-id uint) (member principal))
  (map-get? circle-members { circle-id: circle-id, member: member })
)

(define-read-only (get-circle-milestone (milestone-id uint))
  (map-get? circle-milestones { milestone-id: milestone-id })
)

(define-read-only (get-milestone-completion (milestone-id uint) (member principal))
  (map-get? milestone-completions { milestone-id: milestone-id, member: member })
)

(define-read-only (get-member-circle-count (member principal))
  (default-to { active-circles: u0 } (map-get? circle-membership-count { member: member }))
)

(define-read-only (get-circle-stats (circle-id uint))
  (match (map-get? learning-circles { circle-id: circle-id })
    circle
      (some {
        name: (get name circle),
        current-members: (get current-members circle),
        max-members: (get max-members circle),
        milestones-completed: (get milestones-completed circle),
        total-milestones: (get total-milestones circle),
        reward-pool: (get reward-pool circle),
        is-active: (get is-active circle),
        completion-rate: (if (> (get total-milestones circle) u0)
          (/ (* (get milestones-completed circle) u100) (get total-milestones circle))
          u0
        )
      })
    none
  )
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

(define-private (update-member-circle-count (member principal) (joining bool))
  (let
    (
      (current-count (get active-circles (get-member-circle-count member)))
    )
    (map-set circle-membership-count
      { member: member }
      {
        active-circles: (if joining
          (+ current-count u1)
          (if (> current-count u0)
            (- current-count u1)
            u0
          )
        )
      }
    )
    true
  )
)

(define-private (update-member-contribution (member principal) (circle-id uint))
  (match (map-get? circle-members { circle-id: circle-id, member: member })
    member-data
      (begin
        (map-set circle-members
          { circle-id: circle-id, member: member }
          (merge member-data {
            contribution-score: (+ (get contribution-score member-data) u10),
            milestones-completed: (+ (get milestones-completed member-data) u1)
          })
        )
        (match (map-get? member-addresses { address: member })
          addr-data
            (match (map-get? members { member-id: (get member-id addr-data) })
              member-info
                (map-set members
                  { member-id: (get member-id addr-data) }
                  (merge member-info {
                    reputation: (+ (get reputation member-info) u3)
                  })
                )
              false
            )
          false
        )
        true
      )
    false
  )
)

(define-private (complete-circle-milestone (milestone-id uint))
  (let
    (
      (milestone (unwrap! (map-get? circle-milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
      (circle-id (get circle-id milestone))
    )
    (map-set circle-milestones
      { milestone-id: milestone-id }
      (merge milestone {
        is-completed: true,
        completed-at: (some stacks-block-height)
      })
    )
    (match (map-get? learning-circles { circle-id: circle-id })
      circle
        (map-set learning-circles
          { circle-id: circle-id }
          (merge circle {
            milestones-completed: (+ (get milestones-completed circle) u1)
          })
        )
      false
    )
    (ok true)
  )
)