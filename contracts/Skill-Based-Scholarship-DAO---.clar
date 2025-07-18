(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-PROPOSAL-EXPIRED (err u104))
(define-constant ERR-QUIZ-NOT-FOUND (err u105))
(define-constant ERR-WRONG-ANSWER (err u106))
(define-constant ERR-INSUFFICIENT-TOKENS (err u107))

(define-fungible-token governance-token)

(define-data-var dao-admin principal tx-sender)
(define-data-var proposal-count uint u0)
(define-data-var quiz-count uint u0)
(define-data-var min-tokens-to-vote uint u10)
(define-data-var voting-period uint u144)

(define-map proposals
    uint 
    {
        applicant: principal,
        amount: uint,
        description: (string-ascii 256),
        yes-votes: uint,
        no-votes: uint,
        end-block: uint,
        executed: bool
    }
)

(define-map quizzes
    uint
    {
        question: (string-ascii 256),
        answer: (string-ascii 64),
        tokens-reward: uint
    }
)

(define-map user-votes
    {proposal-id: uint, voter: principal}
    bool
)

(define-map user-quiz-completion
    {quiz-id: uint, user: principal}
    bool
)

(define-public (initialize (admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (var-set dao-admin admin)
        (ok true)
    )
)

(define-public (create-scholarship-proposal (amount uint) (description (string-ascii 256)))
    (let
        (
            (proposal-id (+ (var-get proposal-count) u1))
            (end-block (+ burn-block-height (var-get voting-period)))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (map-set proposals proposal-id
            {
                applicant: tx-sender,
                amount: amount,
                description: description,
                yes-votes: u0,
                no-votes: u0,
                end-block: end-block,
                executed: false
            }
        )
        (var-set proposal-count proposal-id)
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
    (let
        (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (voter-balance (ft-get-balance governance-token tx-sender))
        )
        (asserts! (>= voter-balance (var-get min-tokens-to-vote)) ERR-INSUFFICIENT-TOKENS)
        (asserts! (< stacks-block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (not (default-to false (map-get? user-votes {proposal-id: proposal-id, voter: tx-sender}))) ERR-ALREADY-VOTED)
        
        (map-set user-votes {proposal-id: proposal-id, voter: tx-sender} true)
        
        (if vote
            (map-set proposals proposal-id (merge proposal {yes-votes: (+ (get yes-votes proposal) u1)}))
            (map-set proposals proposal-id (merge proposal {no-votes: (+ (get no-votes proposal) u1)}))
        )
        (ok true)
    )
)

(define-public (create-quiz (question (string-ascii 256)) (answer (string-ascii 64)) (tokens-reward uint))
    (let
        ((quiz-id (+ (var-get quiz-count) u1)))
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (map-set quizzes quiz-id
            {
                question: question,
                answer: answer,
                tokens-reward: tokens-reward
            }
        )
        (var-set quiz-count quiz-id)
        (ok quiz-id)
    )
)

(define-public (submit-quiz-answer (quiz-id uint) (answer (string-ascii 64)))
    (let
        ((quiz (unwrap! (map-get? quizzes quiz-id) ERR-QUIZ-NOT-FOUND)))
        (asserts! (not (default-to false (map-get? user-quiz-completion {quiz-id: quiz-id, user: tx-sender}))) ERR-ALREADY-VOTED)
        (asserts! (is-eq (get answer quiz) answer) ERR-WRONG-ANSWER)
        
        (map-set user-quiz-completion {quiz-id: quiz-id, user: tx-sender} true)
        (try! (ft-mint? governance-token (get tokens-reward quiz) tx-sender))
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let
        ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
        (asserts! (>= stacks-block-height (get end-block proposal)) ERR-PROPOSAL-EXPIRED)
        (asserts! (not (get executed proposal)) ERR-ALREADY-VOTED)
        (asserts! (> (get yes-votes proposal) (get no-votes proposal)) ERR-NOT-AUTHORIZED)
        
        (try! (stx-transfer? (get amount proposal) tx-sender (get applicant proposal)))
        (map-set proposals proposal-id (merge proposal {executed: true}))
        (ok true)
    )
)

(define-read-only (get-proposal (proposal-id uint))
    (ok (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
)

(define-read-only (get-quiz (quiz-id uint))
    (ok (unwrap! (map-get? quizzes quiz-id) ERR-QUIZ-NOT-FOUND))
)

(define-read-only (get-user-vote-status (proposal-id uint) (user principal))
    (ok (default-to false (map-get? user-votes {proposal-id: proposal-id, voter: user})))
)

(define-read-only (get-user-quiz-status (quiz-id uint) (user principal))
    (ok (default-to false (map-get? user-quiz-completion {quiz-id: quiz-id, user: user})))
)
