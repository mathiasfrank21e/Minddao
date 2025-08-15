# 🧠 MindDAO - Mental Health Peer Support DAO

> 🤝 Community-driven mental health care networks powered by blockchain

## 🌟 Overview

MindDAO is a decentralized autonomous organization focused on creating peer-to-peer mental health support networks. Members can offer and receive emotional support, participate in governance, and build a reputation-based community that rewards meaningful contributions to mental wellness.

## ✨ Features

### 👥 Community Membership
- **Join the DAO**: Become a verified community member
- **Reputation System**: Build trust through positive interactions
- **Member Profiles**: Track sessions, ratings, and community contributions

### 🤗 Peer Support Sessions
- **Create Support Sessions**: Offer help to community members
- **Reward System**: Compensate supporters with STX tokens
- **Session Tracking**: Monitor active and completed support interactions
- **Rating & Feedback**: Rate supporters and provide constructive feedback

### 🗳️ Governance & Proposals
- **Community Proposals**: Suggest improvements and initiatives
- **Democratic Voting**: All members can vote on proposals
- **Proposal Execution**: Automatically execute approved proposals
- **Treasury Management**: Community-controlled funding for initiatives

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX tokens

### Installation

```bash
git clone <repository-url>
cd minddao
clarinet check
```

### Usage

#### 1. 🎯 Join the DAO
```clarity
(contract-call? .Minddao join-dao)
```

#### 2. 💝 Create a Support Session
```clarity
(contract-call? .Minddao create-support-session 
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM  ;; seeker address
  "Anxiety Support"                                ;; topic
  u60                                             ;; duration in minutes
  u1000000)                                       ;; reward in microSTX
```

#### 3. ✅ Complete a Session
```clarity
(contract-call? .Minddao complete-session u1)
```

#### 4. ⭐ Rate a Session
```clarity
(contract-call? .Minddao rate-session 
  u1                           ;; session-id
  u5                          ;; rating (1-5)
  "Excellent support!")       ;; feedback
```

#### 5. 📝 Create a Proposal
```clarity
(contract-call? .Minddao create-proposal
  "Mental Health Workshop"                    ;; title
  "Fund a community workshop on mindfulness" ;; description
  u5000000)                                  ;; reward amount
```

#### 6. 🗳️ Vote on Proposals
```clarity
(contract-call? .Minddao vote-proposal u1 true)  ;; proposal-id, vote (true/false)


