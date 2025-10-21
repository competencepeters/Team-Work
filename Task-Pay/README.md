# Collaborative Task Management System

A decentralized smart contract built on the Stacks blockchain for managing collaborative projects, task assignments, and automated payments. This system enables transparent team collaboration with built-in reputation tracking, escrow functionality, and dispute resolution.

## Overview

This smart contract provides a comprehensive platform for decentralized project management where:

- Project owners can create projects and manage team members
- Tasks can be assigned with specific deadlines and reward amounts
- Payments are automated upon task completion
- Team member performance is tracked through reputation metrics
- Disputes can be raised and resolved with escrow protection

## Core Features

### Project Management

**Create Projects**: Initialize new projects with title, description, and budget allocation

**Team Management**: Add team members to projects with role-based access control

**Project Tracking**: Monitor project status and member participation

### Task Assignment

**Task Creation**: Assign tasks to team members with detailed specifications including title, description, deadline, and reward amount

**Status Updates**: Track task progress through status updates by authorized parties

**Task Completion**: Automated payment release upon successful task completion

### Payment System

**Direct Payments**: Original system supports direct STX transfers upon task completion

**Escrow System**: Enhanced payment protection through locked funds until completion or dispute resolution

**Automatic Transfers**: Smart contract handles all payment transfers securely

### Reputation System

**Performance Tracking**: Track completed tasks and total earnings for each team member

**Rating System**: Five-point rating scale for member performance evaluation

**Average Ratings**: Cumulative calculation of member ratings over time

### Dispute Resolution

**Dispute Creation**: Both project owners and assignees can raise disputes with detailed reasons

**Escrow Locking**: Funds are automatically locked when disputes are raised

**Resolution Options**: Disputes can be resolved with either refund to owner or release to assignee

## Error Codes

The contract uses the following error constants:

- `ERR-UNAUTHORIZED-ACCESS (u100)`: Caller lacks required permissions
- `ERR-PROJECT-NOT-FOUND (u101)`: Specified project does not exist
- `ERR-TASK-NOT-FOUND (u102)`: Specified task does not exist
- `ERR-INVALID-STATUS-UPDATE (u103)`: Status update is not permitted
- `ERR-INSUFFICIENT-PROJECT-FUNDS (u104)`: Project has insufficient funds
- `ERR-DUPLICATE-PROJECT-ID (u105)`: Project ID already exists
- `ERR-DUPLICATE-TASK-ID (u106)`: Task ID already exists
- `ERR-INVALID-INPUT (u107)`: Input parameters are invalid

## Public Functions

### Project Functions

**create-project**
```clarity
(create-project (title (string-ascii 50)) (description (string-ascii 500)) (budget uint))
```
Creates a new project and returns the project ID. Validates that title, description, and budget are non-empty/non-zero.

**add-team-member**
```clarity
(add-team-member (project-id uint) (member-address principal))
```
Adds a team member to a project. Only callable by project owner. Maximum 20 members per project.

### Task Functions

**assign-task**
```clarity
(assign-task (project-id uint) (title (string-ascii 50)) (description (string-ascii 500)) 
             (assignee principal) (deadline uint) (reward uint))
```
Creates and assigns a task to a team member. Only callable by project owner. Assignee must be owner or registered member.

**update-task-status**
```clarity
(update-task-status (project-id uint) (task-id uint) (new-status (string-ascii 20)))
```
Updates task status. Callable by project owner or task assignee.

**complete-task**
```clarity
(complete-task (project-id uint) (task-id uint))
```
Marks task as completed and transfers payment directly from project owner to assignee. Only callable by task assignee.

**complete-task-with-escrow**
```clarity
(complete-task-with-escrow (project-id uint) (task-id uint))
```
Completes task and releases funds from escrow. Prevents completion if dispute exists. Updates member statistics.

### Escrow Functions

**fund-task-escrow**
```clarity
(fund-task-escrow (project-id uint) (task-id uint))
```
Deposits task reward into escrow. Only callable by project owner. Transfers STX to contract for safekeeping.

### Dispute Functions

**raise-dispute**
```clarity
(raise-dispute (project-id uint) (task-id uint) (reason (string-ascii 500)))
```
Raises a dispute for a task. Callable by project owner or task assignee. Automatically locks escrow.

**resolve-dispute**
```clarity
(resolve-dispute (project-id uint) (task-id uint) (resolution-type (string-ascii 20)) 
                 (resolution-note (string-ascii 500)))
```
Resolves a dispute. Only callable by project owner. Resolution type can be "release" (pay assignee) or "refund" (return to owner).

### Reputation Functions

**rate-member**
```clarity
(rate-member (member principal) (rating uint))
```
Submits a performance rating for a team member. Rating must be between 1 and 5 inclusive.

## Read-Only Functions

**get-project-info**
```clarity
(get-project-info (project-id uint))
```
Returns complete project information including owner, title, description, budget, status, creation height, and members.

**get-task-info**
```clarity
(get-task-info (project-id uint) (task-id uint))
```
Returns complete task information including assignee, title, description, deadline, reward, and status.

**get-member-stats**
```clarity
(get-member-stats (member-address principal))
```
Returns performance statistics for a team member including tasks completed, total earned, and average rating.

**check-member-authorization**
```clarity
(check-member-authorization (project-id uint) (member-address principal))
```
Checks if an address is authorized as a member of a project.

**get-dispute-info**
```clarity
(get-dispute-info (project-id uint) (task-id uint))
```
Returns dispute information including raised-by, reason, status, and resolution details.

**get-escrow-info**
```clarity
(get-escrow-info (project-id uint) (task-id uint))
```
Returns escrow information including amount, lock status, and depositor.

## Workflow Examples

### Basic Project Flow

1. Create a project using `create-project`
2. Add team members using `add-team-member`
3. Assign tasks to members using `assign-task`
4. Team members complete tasks using `complete-task`
5. Rate member performance using `rate-member`

### Escrow-Protected Flow

1. Create a project and add team members
2. Assign a task to a team member
3. Fund the task escrow using `fund-task-escrow`
4. Team member completes task using `complete-task-with-escrow`
5. Funds are automatically released from escrow

### Dispute Resolution Flow

1. After task assignment and escrow funding, if issues arise
2. Either party raises dispute using `raise-dispute`
3. Escrow is automatically locked
4. Project owner reviews and resolves using `resolve-dispute`
5. Funds are either released to assignee or refunded to owner

## Security Features

- Role-based access control ensures only authorized parties can perform sensitive operations
- Escrow system protects both project owners and task assignees
- Dispute resolution provides recourse for both parties
- Validation of all inputs prevents malicious or erroneous data
- Automated payment transfers eliminate manual intervention risks

## Data Structures

The contract maintains several data maps:

- **projects**: Stores project metadata and team member lists
- **tasks**: Stores task assignments and completion status
- **member-stats**: Tracks performance metrics for all team members
- **task-escrow**: Holds locked funds for task payments
- **task-disputes**: Records dispute information and resolutions

## Limitations

- Maximum 20 team members per project
- String fields have character limits (50 for titles, 500 for descriptions)
- Dispute resolution currently restricted to project owners
- Rating system uses integer averages (no decimal precision)