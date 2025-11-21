# 🎓 Skill-Based Scholarship DAO

A decentralized autonomous organization (DAO) for managing skill-based scholarships on the Stacks blockchain.

## 🌟 Features

- Create and manage scholarship proposals
- Skill-based quiz system with token rewards
- Democratic voting mechanism
- Transparent fund distribution
- On-chain proposal tracking

## 🔧 Smart Contract Functions

### Governance
- `initialize`: Set up the DAO admin
- `create-scholarship-proposal`: Submit new scholarship proposals
- `vote-on-proposal`: Cast votes on active proposals
- `execute-proposal`: Distribute approved scholarship funds

### Quiz System
- `create-quiz`: Admin can create skill-testing quizzes
- `submit-quiz-answer`: Users can answer quizzes to earn governance tokens

### Read-Only Functions
- `get-proposal`: View proposal details
- `get-quiz`: View quiz information
- `get-user-vote-status`: Check if a user has voted
- `get-user-quiz-status`: Check if a user has completed a quiz

## 🚀 Getting Started

1. Deploy the contract using Clarinet
2. Initialize the DAO with an admin address
3. Create quizzes to enable token earning
4. Users can participate by taking quizzes and earning tokens
5. Token holders can vote on scholarship proposals

## 💡 Usage Example

```clarity
;; Create a new scholarship proposal
(contract-call? .skill-based-scholarship-dao create-scholarship-proposal u1000 "Computer Science Scholarship 2024")

;; Submit a quiz answer
(contract-call? .skill-based-scholarship-dao submit-quiz-answer u1 "correct-answer")

;; Vote on a proposal
(contract-call? .skill-based-scholarship-dao vote-on-proposal u1 true)
```

## 🔒 Security

- Minimum token requirement for voting
- Time-locked proposal execution
- Admin-only quiz creation
- One vote per proposal per user
```
