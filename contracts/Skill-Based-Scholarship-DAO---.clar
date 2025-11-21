(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-PROPOSAL-EXPIRED (err u104))
(define-constant ERR-QUIZ-NOT-FOUND (err u105))
(define-constant ERR-WRONG-ANSWER (err u106))
(define-constant ERR-INSUFFICIENT-TOKENS (err u107))
(define-constant ERR-ALREADY-REVIEWED (err u108))
(define-constant ERR-NOT-REVIEWER (err u109))
(define-constant ERR-INSUFFICIENT-REVIEWS (err u110))
(define-constant ERR-CANNOT-DELEGATE-TO-SELF (err u111))
(define-constant ERR-DELEGATION-CYCLE (err u112))
(define-constant ERR-PAUSED (err u113))

(define-fungible-token governance-token)

(define-data-var dao-admin principal tx-sender)
(define-data-var proposal-count uint u0)
(define-data-var quiz-count uint u0)
(define-data-var min-tokens-to-vote uint u10)
(define-data-var voting-period uint u144)
(define-data-var min-reviews-required uint u3)
(define-data-var is-paused bool false)

(define-map proposals
    uint
    {
        applicant: principal,
        amount: uint,
        description: (string-ascii 256),
        yes-votes: uint,
        no-votes: uint,
        end-block: uint,
        executed: bool,
        approved-reviews: uint,
        rejected-reviews: uint,
        review-complete: bool,
    }
)

(define-map quizzes
    uint
    {
        question: (string-ascii 256),
        answer: (string-ascii 64),
        tokens-reward: uint,
    }
)

(define-map user-votes
    {
        proposal-id: uint,
        voter: principal,
    }
    bool
)

(define-map user-quiz-completion
    {
        quiz-id: uint,
        user: principal,
    }
    bool
)

(define-map proposal-reviews
    {
        proposal-id: uint,
        reviewer: principal,
    }
    bool
)

(define-map authorized-reviewers
    principal
    bool
)

(define-map vote-delegations
    principal
    principal
)

(define-map delegation-counts
    principal
    uint
)

(define-public (initialize (admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (var-set dao-admin admin)
        (ok true)
    )
)

(define-public (set-paused (value bool))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (var-set is-paused value)
        (ok true)
    )
)

(define-read-only (get-paused)
    (ok (var-get is-paused))
)

(define-public (create-scholarship-proposal
        (amount uint)
        (description (string-ascii 256))
    )
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (let (
                (proposal-id (+ (var-get proposal-count) u1))
                (end-block (+ burn-block-height (var-get voting-period)))
            )
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            (map-set proposals proposal-id {
                applicant: tx-sender,
                amount: amount,
                description: description,
                yes-votes: u0,
                no-votes: u0,
                end-block: end-block,
                executed: false,
                approved-reviews: u0,
                rejected-reviews: u0,
                review-complete: false,
            })
            (var-set proposal-count proposal-id)
            (ok proposal-id)
        )
    )
)

(define-public (vote-on-proposal
        (proposal-id uint)
        (vote bool)
    )
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (let (
                (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
                (voter-balance (ft-get-balance governance-token tx-sender))
                (delegated-power (default-to u0 (map-get? delegation-counts tx-sender)))
                (total-voting-power (+ voter-balance delegated-power))
            )
            (asserts! (>= voter-balance (var-get min-tokens-to-vote))
                ERR-INSUFFICIENT-TOKENS
            )
            (asserts! (< stacks-block-height (get end-block proposal))
                ERR-PROPOSAL-EXPIRED
            )
            (asserts! (get review-complete proposal) ERR-INSUFFICIENT-REVIEWS)
            (asserts!
                (not (default-to false
                    (map-get? user-votes {
                        proposal-id: proposal-id,
                        voter: tx-sender,
                    })
                ))
                ERR-ALREADY-VOTED
            )
            (map-set user-votes {
                proposal-id: proposal-id,
                voter: tx-sender,
            }
                true
            )
            (if vote
                (map-set proposals proposal-id
                    (merge proposal { yes-votes: (+ (get yes-votes proposal) total-voting-power) })
                )
                (map-set proposals proposal-id
                    (merge proposal { no-votes: (+ (get no-votes proposal) total-voting-power) })
                )
            )
            (ok true)
        )
    )
)

(define-public (create-quiz
        (question (string-ascii 256))
        (answer (string-ascii 64))
        (tokens-reward uint)
    )
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (let ((quiz-id (+ (var-get quiz-count) u1)))
            (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
            (map-set quizzes quiz-id {
                question: question,
                answer: answer,
                tokens-reward: tokens-reward,
            })
            (var-set quiz-count quiz-id)
            (ok quiz-id)
        )
    )
)

(define-public (submit-quiz-answer
        (quiz-id uint)
        (answer (string-ascii 64))
    )
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (let ((quiz (unwrap! (map-get? quizzes quiz-id) ERR-QUIZ-NOT-FOUND)))
            (asserts!
                (not (default-to false
                    (map-get? user-quiz-completion {
                        quiz-id: quiz-id,
                        user: tx-sender,
                    })
                ))
                ERR-ALREADY-VOTED
            )
            (asserts! (is-eq (get answer quiz) answer) ERR-WRONG-ANSWER)
            (map-set user-quiz-completion {
                quiz-id: quiz-id,
                user: tx-sender,
            }
                true
            )
            (try! (ft-mint? governance-token (get tokens-reward quiz) tx-sender))
            (ok true)
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
            (asserts! (>= stacks-block-height (get end-block proposal))
                ERR-PROPOSAL-EXPIRED
            )
            (asserts! (not (get executed proposal)) ERR-ALREADY-VOTED)
            (asserts! (> (get yes-votes proposal) (get no-votes proposal))
                ERR-NOT-AUTHORIZED
            )
            (try! (stx-transfer? (get amount proposal) tx-sender
                (get applicant proposal)
            ))
            (map-set proposals proposal-id (merge proposal { executed: true }))
            (ok true)
        )
    )
)

(define-read-only (get-proposal (proposal-id uint))
    (ok (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
)

(define-read-only (get-quiz (quiz-id uint))
    (ok (unwrap! (map-get? quizzes quiz-id) ERR-QUIZ-NOT-FOUND))
)

(define-read-only (get-user-vote-status
        (proposal-id uint)
        (user principal)
    )
    (ok (default-to false
        (map-get? user-votes {
            proposal-id: proposal-id,
            voter: user,
        })
    ))
)

(define-read-only (get-user-quiz-status
        (quiz-id uint)
        (user principal)
    )
    (ok (default-to false
        (map-get? user-quiz-completion {
            quiz-id: quiz-id,
            user: user,
        })
    ))
)

(define-public (add-reviewer (reviewer principal))
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (map-set authorized-reviewers reviewer true)
        (ok true)
    )
)

(define-public (remove-reviewer (reviewer principal))
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (map-delete authorized-reviewers reviewer)
        (ok true)
    )
)

(define-public (review-proposal
        (proposal-id uint)
        (approve bool)
    )
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (let (
                (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
                (is-reviewer (default-to false (map-get? authorized-reviewers tx-sender)))
            )
            (asserts! is-reviewer ERR-NOT-REVIEWER)
            (asserts!
                (not (default-to false
                    (map-get? proposal-reviews {
                        proposal-id: proposal-id,
                        reviewer: tx-sender,
                    })
                ))
                ERR-ALREADY-REVIEWED
            )
            (map-set proposal-reviews {
                proposal-id: proposal-id,
                reviewer: tx-sender,
            }
                true
            )
            (let (
                    (updated-proposal (if approve
                        (merge proposal { approved-reviews: (+ (get approved-reviews proposal) u1) })
                        (merge proposal { rejected-reviews: (+ (get rejected-reviews proposal) u1) })
                    ))
                    (total-reviews (+ (get approved-reviews updated-proposal)
                        (get rejected-reviews updated-proposal)
                    ))
                )
                (map-set proposals proposal-id updated-proposal)
                (if (>= total-reviews (var-get min-reviews-required))
                    (map-set proposals proposal-id
                        (merge updated-proposal { review-complete: true })
                    )
                    true
                )
                (ok true)
            )
        )
    )
)

(define-read-only (get-reviewer-status (reviewer principal))
    (ok (default-to false (map-get? authorized-reviewers reviewer)))
)

(define-read-only (get-proposal-review-status
        (proposal-id uint)
        (reviewer principal)
    )
    (ok (default-to false
        (map-get? proposal-reviews {
            proposal-id: proposal-id,
            reviewer: reviewer,
        })
    ))
)

(define-public (delegate-voting-power (delegate-to principal))
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (let (
                (current-delegate (map-get? vote-delegations tx-sender))
                (delegator-balance (ft-get-balance governance-token tx-sender))
            )
            (asserts! (not (is-eq tx-sender delegate-to))
                ERR-CANNOT-DELEGATE-TO-SELF
            )
            (asserts! (is-none (map-get? vote-delegations delegate-to))
                ERR-DELEGATION-CYCLE
            )
            (asserts! (> delegator-balance u0) ERR-INSUFFICIENT-TOKENS)
            (match current-delegate
                old-delegate (let ((old-count (default-to u0 (map-get? delegation-counts old-delegate))))
                    (if (> old-count u0)
                        (map-set delegation-counts old-delegate
                            (- old-count delegator-balance)
                        )
                        true
                    )
                )
                true
            )
            (let ((new-count (default-to u0 (map-get? delegation-counts delegate-to))))
                (map-set delegation-counts delegate-to
                    (+ new-count delegator-balance)
                )
            )
            (map-set vote-delegations tx-sender delegate-to)
            (ok true)
        )
    )
)

(define-public (revoke-delegation)
    (begin
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (let (
                (current-delegate (unwrap! (map-get? vote-delegations tx-sender) ERR-NOT-AUTHORIZED))
                (delegator-balance (ft-get-balance governance-token tx-sender))
                (current-count (default-to u0 (map-get? delegation-counts current-delegate)))
            )
            (if (> current-count u0)
                (map-set delegation-counts current-delegate
                    (- current-count delegator-balance)
                )
                true
            )
            (map-delete vote-delegations tx-sender)
            (ok true)
        )
    )
)

(define-read-only (get-delegate (delegator principal))
    (ok (map-get? vote-delegations delegator))
)

(define-read-only (get-voting-power (voter principal))
    (let (
            (token-balance (ft-get-balance governance-token voter))
            (delegated-power (default-to u0 (map-get? delegation-counts voter)))
        )
        (ok (+ token-balance delegated-power))
    )
)
