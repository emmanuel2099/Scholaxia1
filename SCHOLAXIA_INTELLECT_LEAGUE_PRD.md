# SCHOLAXIA INTELLECT LEAGUE (SIL)

## Product Requirements Document (PRD) v1.0

This file preserves the full SIL PRD. Do not remove requirements from this document when shipping features — implement toward full coverage.

---

# 1. Overview

Scholaxia Intellect League (SIL) is a nationwide academic competition built into the Scholaxia Student App.

Students compete by answering timed academic questions, earning Scholaxia Coins, improving their rankings, and representing their class and school.

The goal is to make learning competitive, engaging, and rewarding while ensuring fair play through strong anti-cheat measures.

---

# 2. User Roles

The Scholaxia App has four user roles:

* Kid
* Student
* Teacher
* Parent (if applicable in the main app)

The Intellect League is available to **Students**.

The Scholaxia App also supports:

* Kid
* Student
* Teacher
* Game Challenge (Scholaxia Intellect League)

The **Game Challenge** role is a dedicated competitive experience within Scholaxia. Students who want to participate in the Scholaxia Intellect League must register for this role by completing the League onboarding process (school selection, class verification, face verification, gamer tag creation, and acceptance of League rules).

Once registration is complete, the user gains access to all League features.

---

# 3. Student App Navigation

The Student App navigation remains:

* Home
* Community
* Groups
* Profile

There is **no permanent Challenge tab**.

Students discover the League through banners, notifications, community posts, and challenge invitations.

---

# 3b. Accessing the Game Challenge

The Student role already exists in the main Scholaxia application and should **not** be modified.

The **Game Challenge** is introduced as an additional role entry point.

Students can discover and access the Game Challenge through:

* Home screen promotional banners
* Community announcements
* Challenge invitations
* Notifications
* Friday National Challenge promotions
* Leaderboards and featured winners
* Role select → Game Challenge login/signup

If the student has not registered for the League, selecting any Game Challenge entry point opens the League registration process.

If the student is already registered, selecting any Game Challenge entry point opens the League Dashboard.

---

# 4. Home Banner System

A dynamic banner appears on the Home screen.

Examples:

* Join Scholaxia Intellect League
* Friday National Challenge is Live
* Live School Match
* Buy Scholaxia Coins
* Scholarship Opportunities
* Study Resources
* Student Deals (e.g., discounted data)
* Winner Announcements

Selecting a League banner opens the League registration (if not enrolled) or the League dashboard (if already enrolled).

---

# 5. League Registration

Students complete registration only once.

Steps:

1. Welcome Screen
2. Select Country
3. Select State
4. Select School
5. Select Class
6. Face Verification
7. Create Gamer Tag
8. Accept League Rules

After successful registration:

* League Wallet is created.
* League Profile is created.
* Student receives starting rank.
* Student enters the League.

---

# 6. Face Verification

Face verification is mandatory.

During registration:

* Student captures a selfie.
* Backend stores a secure face template (embedding), not just an image.

Before every competition:

* Face verification is required.
* Liveness detection is performed.

During competition:

* Front camera remains active.
* Only the registered player is allowed.

The system monitors:

* Registered face
* Single face only
* Face inside camera frame
* Camera not covered

Repeated violations result in forfeiture according to platform rules.

---

## 18.1 Continuous Identity Verification

### Before Match

Before any competition begins, the player must successfully complete:

* Face Verification
* Liveness Detection

Only verified players are allowed to start a match.

### During Match

While the competition is in progress:

* The front camera must remain active.
* The system continuously verifies that the registered player remains present.
* Only one face may appear in the camera.
* The player's face must remain visible throughout the competition.

If verification fails repeatedly according to platform rules, the player forfeits the match.

### App Background Detection

During any live competition:

* The player must remain inside the Scholaxia application.
* Minimizing the app, switching to another app, or sending Scholaxia to the background immediately pauses gameplay.

Before the player can continue, the system must perform a new face verification.

The player cannot resume the match until identity verification is successful.

If the player fails verification or exceeds the allowed interruption time, the match is automatically forfeited.

### Device Lock

During live competitions:

* Screen recording is not permitted.
* Split-screen mode is not permitted.
* Floating applications are not permitted.
* Overlay applications are not permitted.
* Multiple active sessions on different devices are not permitted.

Any violation is logged and evaluated by the anti-cheat system.

### Re-entry Verification

Whenever a player:

* Returns from the background,
* Unlocks the device during a match,
* Reconnects after a network interruption,
* Or resumes a paused competition,

the system must require an immediate face verification before gameplay continues.

### Security Objective

These verification rules ensure that:

* The registered student starts the competition.
* The same student completes the competition.
* No substitute player can continue a match.
* Identity is verified throughout the entire competition lifecycle.

---

# 7. Competition Modes

## A. Practice Mode

Purpose: Practice without risk.

Features:

* Unlimited practice
* No betting
* No rewards
* No ranking changes

## B. AI Challenge

Students compete against the computer.

Levels:

* Level 1 – Beginner
* Level 2 – Easy
* Level 3 – Medium
* Level 4 – Hard
* Level 5 – Expert
* Level 6 – Genius

Each level has:

* Entry Coin requirement
* Reward Coins
* Increasing difficulty

Winning rewards coins from the Scholaxia reward pool.

Losing forfeits the entry coins.

Daily reward limits and progression rules should prevent unlimited farming.

## C. Student Challenge

Student vs Student.

Requirements:

* Same academic class only.
* Students may come from different schools.
* Live competition.

Match format:

* 5 Questions
* 20 Seconds each

Allowed bets:

* 50 Coins
* 100 Coins
* 200 Coins
* 500 Coins

Winner receives 90% of the total pot.

Scholaxia retains 10% as the platform fee.

## D. Class Challenge

Class vs Class.

Requirements:

* Same academic class
* Different schools

Team size: 5 vs 5

Questions: 10

Winning team shares the prize pool.

## E. School Challenge

School vs School.

Requirements: School Captain selects one class.

Each school fields: 10 students.

Invitation flow:

* School sends invitation.
* Opponent has 48 hours to Accept or Reject.

Winning school receives:

* 90% of prize pool
* School Trophy
* School Rank Points

---

# 8. Friday National Challenge

Every Friday, Scholaxia hosts a nationwide event.

Purpose: Weekly national academic championship.

Includes:

* School battles
* National rankings
* Featured matches
* Special rewards
* Community highlights

Saturday is reserved for announcing champions and publishing rankings.

---

# 9. Match Rules

Every match:

* Live
* Server controlled
* Timer enforced
* Automatic scoring

Server decides:

* Questions
* Timing
* Correct answers
* Winner

Client only displays information.

---

# 10. Class Lock

Students only compete within the same academic class.

Backend must enforce this rule.

---

# 11. Betting System

Both players stake the same amount.

Platform Fee: 10%

Winner receives 90% of the pot.

Coins are automatically credited to the winner's wallet.

---

# 12. Wallet

Every League user has:

* Coin Balance
* Transaction History
* Buy Coins
* Withdraw / Redeem
* Rewards

Every transaction must be logged.

---

# 13. Coin Purchase

Students purchase coins through supported payment methods (e.g., Paystack).

No coins = no paid competition.

---

# 14. Rewards

Students earn:

* Coins
* XP
* Badges
* Rankings
* Trophies

---

# 15. Rankings

Leaderboards include:

Students

* National
* State
* School

Schools

* National Ranking

Classes

* Best JSS1
* Best JSS2
* Best SSS1
* etc.

Friday Challenges update national rankings.

---

# 16. Community Integration

Competition updates appear inside Community.

Examples:

* David defeated Mary.
* Scholaxia Academy won today's battle.
* Sarah reached Rank #1.
* Friday Challenge has started.
* New National Champion announced.

Students can:

* Like
* Comment
* Celebrate

---

# 17. Notifications

Examples:

* You have been challenged.
* Friday Challenge starts in 1 hour.
* You won 360 Coins.
* Your school moved to Rank #3.
* You received a reward.

---

# 18. Anti-Cheat System

* Face verification
* Liveness detection
* Front camera monitoring
* One face only
* Face remains in frame
* Root/Jailbreak detection
* Emulator detection
* Secure server-side scoring
* App background detection
* Device monitoring
* Suspicious behavior analysis
* Human review for flagged matches

Server is always the source of truth.

---

# 19. Question Engine

Questions are categorized by:

* Subject
* Academic Class
* Difficulty

Question sets are generated per match.

Answer options are randomized.

Questions must match the student's verified class level.

---

# 20. School Profiles

Every school has:

* Logo
* Name
* State
* National Rank
* School Captain
* Trophy Cabinet
* Top Players
* Match History

---

# 21. Student Profiles

League Profile includes:

* Gamer Tag
* Coins
* Rank
* Wins
* Losses
* Win Rate
* Current Streak
* School
* Class
* Badges

---

# 22. League Dashboard

After registration, students access:

* Play vs Computer
* Challenge Student
* Class Challenge
* School Challenge
* Wallet
* Leaderboards
* Match History
* Rewards

---

# 23. Admin Features

Admin Portal should support:

* Manage Schools
* Manage Questions
* Review Reported Matches
* Manage Rewards
* Manage Coin Economy
* View Analytics
* Moderate Community League Posts
* Manage Friday National Challenges

---

# 24. Success Metrics

* Daily Active Players
* Friday Challenge Participation
* Matches Played
* Coins Purchased
* Coins Won
* Average Match Completion
* Anti-Cheat Violations
* School Participation
* Student Retention
* Community Engagement

---

# Vision

Scholaxia Intellect League is designed to become Nigeria's leading academic esports platform, allowing students to learn, compete, represent their schools, earn rewards, and build a national academic reputation through fair, secure, and engaging competitions.
