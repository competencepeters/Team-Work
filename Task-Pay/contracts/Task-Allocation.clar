;; Collaborative Task Management System Smart Contract
;; A decentralized platform for managing projects, assigning tasks to team members,
;; tracking task completion, and automating STX payments upon successful delivery.
;; This contract enables transparent collaboration with built-in reputation tracking.

;; Error constants for contract operations
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-PROJECT-NOT-FOUND (err u101))
(define-constant ERR-TASK-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATUS-UPDATE (err u103))
(define-constant ERR-INSUFFICIENT-PROJECT-FUNDS (err u104))
(define-constant ERR-DUPLICATE-PROJECT-ID (err u105))
(define-constant ERR-DUPLICATE-TASK-ID (err u106))
(define-constant ERR-INVALID-INPUT (err u107))

;; Storage map for project information indexed by unique project ID
(define-map projects
    { project-id: uint }
    {
        owner: principal,
        title: (string-ascii 50),
        description: (string-ascii 500),
        total-budget: uint,
        current-status: (string-ascii 20),
        created-at-height: uint,
        members: (list 20 principal),
        project-id-copy: uint
    }
)

;; Storage map for task assignments indexed by project ID and task ID combination
(define-map tasks
    { project-id: uint, task-id: uint }
    {
        assignee: principal,
        title: (string-ascii 50),
        description: (string-ascii 500),
        deadline-height: uint,
        reward-amount: uint,
        current-status: (string-ascii 20),
        created-at-height: uint,
        project-id-copy: uint,
        task-id-copy: uint
    }
)

;; Counter for generating sequential project IDs
(define-map project-id-counter
    { counter-key: (string-ascii 10) }
    { next-id: uint }
)

;; Counter for generating sequential task IDs within each project
(define-map task-id-counter
    { project-id: uint }
    { next-id: uint }
)

;; Performance tracking for team members across all projects
(define-map member-stats
    { member-address: principal }
    {
        tasks-completed: uint,
        total-earned: uint,
        average-rating: uint,
        total-ratings: uint,
        member-address-copy: principal
    }
)

;; Validates that the caller is the owner of the specified project
(define-private (is-project-owner (project-id uint) (caller principal))
    (match (map-get? projects { project-id: project-id })
        project-info (is-eq (get owner project-info) caller)
        false
    )
)

;; Checks if caller is either the project owner or a registered team member
(define-private (is-authorized-member (project-id uint) (caller principal))
    (match (map-get? projects { project-id: project-id })
        project-info (or
            (is-eq (get owner project-info) caller)
            (is-some (index-of (get members project-info) caller))
        )
        false
    )
)

;; Generates and returns the next available project ID
(define-private (get-next-project-id)
    (let ((counter-info (default-to { next-id: u0 } (map-get? project-id-counter { counter-key: "projects" }))))
        (begin
            (map-set project-id-counter { counter-key: "projects" } { next-id: (+ (get next-id counter-info) u1) })
            (get next-id counter-info)
        )
    )
)

;; Generates and returns the next available task ID for a specific project
(define-private (get-next-task-id (project-id uint))
    (match (map-get? projects { project-id: project-id })
        project-info 
            (let ((counter-info (default-to { next-id: u0 } (map-get? task-id-counter { project-id: project-id }))))
                (begin
                    (map-set task-id-counter { project-id: project-id } { next-id: (+ (get next-id counter-info) u1) })
                    (ok (get next-id counter-info))
                )
            )
        ERR-PROJECT-NOT-FOUND
    )
)

;; Creates a new project with title, description, and budget allocation
;; Returns the newly created project ID on success
(define-public (create-project (title (string-ascii 50)) (description (string-ascii 500)) (budget uint))
    (let
        (
            (new-project-id (get-next-project-id))
            (creator tx-sender)
        )
        (if (and 
                (> (len title) u0)
                (> (len description) u0)
                (> budget u0)
            )
            (begin
                (map-set projects
                    { project-id: new-project-id }
                    {
                        owner: creator,
                        title: title,
                        description: description,
                        total-budget: budget,
                        current-status: "active",
                        created-at-height: block-height,
                        members: (list),
                        project-id-copy: new-project-id
                    }
                )
                (ok new-project-id)
            )
            ERR-INVALID-INPUT
        )
    )
)

;; Adds a new team member to an existing project
;; Only the project owner can add members
(define-public (add-team-member (project-id uint) (member-address principal))
    (let
        (
            (caller tx-sender)
        )
        (match (map-get? projects { project-id: project-id })
            project-data
                (let
                    (
                        (validated-project-id (get project-id-copy project-data))
                    )
                    (begin
                        (asserts! (is-eq (get owner project-data) caller) ERR-UNAUTHORIZED-ACCESS)
                        (asserts! (is-none (index-of (get members project-data) member-address)) ERR-INVALID-INPUT)
                        (map-set projects
                            { project-id: validated-project-id }
                            (merge project-data { 
                                members: (unwrap! (as-max-len? (append (get members project-data) member-address) u20) ERR-INVALID-INPUT) 
                            })
                        )
                        (ok true)
                    )
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

;; Creates a new task assignment within a project
;; Tasks include title, description, assignee, deadline, and reward amount
;; Only project owners can create tasks
(define-public (assign-task
    (project-id uint)
    (title (string-ascii 50))
    (description (string-ascii 500))
    (assignee principal)
    (deadline uint)
    (reward uint)
)
    (let
        (
            (caller tx-sender)
        )
        (match (map-get? projects { project-id: project-id })
            project-data
                (let
                    (
                        (validated-project-id (get project-id-copy project-data))
                    )
                    (begin
                        (asserts! (is-eq (get owner project-data) caller) ERR-UNAUTHORIZED-ACCESS)
                        (asserts! (> (len title) u0) ERR-INVALID-INPUT)
                        (asserts! (> (len description) u0) ERR-INVALID-INPUT)
                        (asserts! (> deadline block-height) ERR-INVALID-INPUT)
                        (asserts! (> reward u0) ERR-INVALID-INPUT)
                        (asserts! (or
                            (is-eq assignee (get owner project-data))
                            (is-some (index-of (get members project-data) assignee))
                        ) ERR-INVALID-INPUT)
                        
                        (match (get-next-task-id validated-project-id)
                            new-task-id
                                (begin
                                    (map-set tasks
                                        { project-id: validated-project-id, task-id: new-task-id }
                                        {
                                            assignee: assignee,
                                            title: title,
                                            description: description,
                                            deadline-height: deadline,
                                            reward-amount: reward,
                                            current-status: "pending",
                                            created-at-height: block-height,
                                            project-id-copy: validated-project-id,
                                            task-id-copy: new-task-id
                                        }
                                    )
                                    (ok new-task-id)
                                )
                            error-val ERR-PROJECT-NOT-FOUND
                        )
                    )
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

;; Updates the status of an existing task
;; Both project owner and task assignee can update status
(define-public (update-task-status (project-id uint) (task-id uint) (new-status (string-ascii 20)))
    (let
        (
            (caller tx-sender)
        )
        (match (map-get? projects { project-id: project-id })
            project-data
                (match (map-get? tasks { project-id: project-id, task-id: task-id })
                    task-data
                        (let
                            (
                                (validated-project-id (get project-id-copy task-data))
                                (validated-task-id (get task-id-copy task-data))
                            )
                            (begin
                                (asserts! (or 
                                    (is-eq (get owner project-data) caller) 
                                    (is-eq (get assignee task-data) caller)
                                ) ERR-UNAUTHORIZED-ACCESS)
                                (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)
                                
                                (map-set tasks
                                    { project-id: validated-project-id, task-id: validated-task-id }
                                    (merge task-data { current-status: new-status })
                                )
                                (ok true)
                            )
                        )
                    ERR-TASK-NOT-FOUND
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

;; Completes a task and triggers automatic payment to the assignee
;; Only the task assignee can mark their task as completed
;; Updates member statistics upon successful completion
(define-public (complete-task (project-id uint) (task-id uint))
    (let
        (
            (caller tx-sender)
        )
        (match (map-get? projects { project-id: project-id })
            project-data
                (match (map-get? tasks { project-id: project-id, task-id: task-id })
                    task-data
                        (let
                            (
                                (validated-project-id (get project-id-copy task-data))
                                (validated-task-id (get task-id-copy task-data))
                            )
                            (begin
                                (asserts! (is-eq (get assignee task-data) caller) ERR-UNAUTHORIZED-ACCESS)
                                (asserts! (is-eq (get current-status task-data) "pending") ERR-UNAUTHORIZED-ACCESS)
                                
                                (try! (stx-transfer? (get reward-amount task-data) (get owner project-data) caller))
                                (map-set tasks
                                    { project-id: validated-project-id, task-id: validated-task-id }
                                    (merge task-data { current-status: "completed" })
                                )
                                (let ((current-stats (default-to
                                        { tasks-completed: u0, total-earned: u0, average-rating: u0, total-ratings: u0, member-address-copy: caller }
                                        (map-get? member-stats { member-address: caller })
                                    )))
                                    (map-set member-stats
                                        { member-address: caller }
                                        {
                                            tasks-completed: (+ (get tasks-completed current-stats) u1),
                                            total-earned: (+ (get total-earned current-stats) (get reward-amount task-data)),
                                            average-rating: (get average-rating current-stats),
                                            total-ratings: (get total-ratings current-stats),
                                            member-address-copy: caller
                                        }
                                    )
                                )
                                (ok true)
                            )
                        )
                    ERR-TASK-NOT-FOUND
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

;; Submits a performance rating for a team member
;; Rating must be between 1 and 5 inclusive
;; Updates the member's average rating using cumulative calculation
(define-public (rate-member (member principal) (rating uint))
    (begin
        (asserts! (>= rating u1) ERR-INVALID-INPUT)
        (asserts! (<= rating u5) ERR-INVALID-INPUT)
        
        (let
            (
                (current-stats (default-to
                    { tasks-completed: u0, total-earned: u0, average-rating: u0, total-ratings: u0, member-address-copy: member }
                    (map-get? member-stats { member-address: member })
                ))
                (validated-member (get member-address-copy (default-to
                    { tasks-completed: u0, total-earned: u0, average-rating: u0, total-ratings: u0, member-address-copy: member }
                    (map-get? member-stats { member-address: member })
                )))
            )
            (map-set member-stats
                { member-address: validated-member }
                {
                    tasks-completed: (get tasks-completed current-stats),
                    total-earned: (get total-earned current-stats),
                    average-rating: (/ (+ (* (get average-rating current-stats) (get total-ratings current-stats)) rating) (+ (get total-ratings current-stats) u1)),
                    total-ratings: (+ (get total-ratings current-stats) u1),
                    member-address-copy: validated-member
                }
            )
            (ok true)
        )
    )
)

;; Retrieves complete information about a specific project
(define-read-only (get-project-info (project-id uint))
    (map-get? projects { project-id: project-id })
)

;; Retrieves complete information about a specific task
(define-read-only (get-task-info (project-id uint) (task-id uint))
    (map-get? tasks { project-id: project-id, task-id: task-id })
)

;; Retrieves performance statistics for a team member
(define-read-only (get-member-stats (member-address principal))
    (map-get? member-stats { member-address: member-address })
)

;; Checks if a given address is authorized as a member of a project
(define-read-only (check-member-authorization (project-id uint) (member-address principal))
    (is-authorized-member project-id member-address)
)

;; ============================================================================
;; DISPUTE RESOLUTION & ESCROW SYSTEM
;; ============================================================================

;; Storage for task disputes
(define-map task-disputes
    { project-id: uint, task-id: uint }
    {
        raised-by: principal,
        reason: (string-ascii 500),
        status: (string-ascii 20),
        raised-at-height: uint,
        resolved-at-height: (optional uint),
        resolution: (optional (string-ascii 500)),
        project-id-copy: uint,
        task-id-copy: uint
    }
)

;; Escrow to hold task rewards until completion or dispute resolution
(define-map task-escrow
    { project-id: uint, task-id: uint }
    {
        amount: uint,
        is-locked: bool,
        deposited-by: principal,
        project-id-copy: uint,
        task-id-copy: uint
    }
)

;; Dispute resolution votes (for community governance)
(define-map dispute-votes
    { project-id: uint, task-id: uint, voter: principal }
    {
        vote: (string-ascii 20),
        voted-at-height: uint
    }
)

;; Funds a task by depositing reward into escrow
;; Only project owner can fund tasks
;; Escrow ensures payment security for both parties
(define-public (fund-task-escrow (project-id uint) (task-id uint))
    (let
        (
            (caller tx-sender)
        )
        (match (map-get? projects { project-id: project-id })
            project-data
                (match (map-get? tasks { project-id: project-id, task-id: task-id })
                    task-data
                        (let
                            (
                                (validated-project-id (get project-id-copy task-data))
                                (validated-task-id (get task-id-copy task-data))
                            )
                            (begin
                                (asserts! (is-eq (get owner project-data) caller) ERR-UNAUTHORIZED-ACCESS)
                                
                                ;; Transfer funds from project owner to contract
                                (try! (stx-transfer? (get reward-amount task-data) caller (as-contract tx-sender)))
                                ;; Record in escrow
                                (map-set task-escrow
                                    { project-id: validated-project-id, task-id: validated-task-id }
                                    {
                                        amount: (get reward-amount task-data),
                                        is-locked: true,
                                        deposited-by: caller,
                                        project-id-copy: validated-project-id,
                                        task-id-copy: validated-task-id
                                    }
                                )
                                (ok true)
                            )
                        )
                    ERR-TASK-NOT-FOUND
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

;; Raises a dispute for a task
;; Can be raised by project owner or task assignee
;; Locks the escrow until resolution
(define-public (raise-dispute (project-id uint) (task-id uint) (reason (string-ascii 500)))
    (let
        (
            (caller tx-sender)
        )
        (match (map-get? projects { project-id: project-id })
            project-data
                (match (map-get? tasks { project-id: project-id, task-id: task-id })
                    task-data
                        (let
                            (
                                (validated-project-id (get project-id-copy task-data))
                                (validated-task-id (get task-id-copy task-data))
                            )
                            (begin
                                (asserts! (> (len reason) u0) ERR-INVALID-INPUT)
                                (asserts! (or 
                                    (is-eq (get owner project-data) caller)
                                    (is-eq (get assignee task-data) caller)
                                ) ERR-UNAUTHORIZED-ACCESS)
                                
                                (map-set task-disputes
                                    { project-id: validated-project-id, task-id: validated-task-id }
                                    {
                                        raised-by: caller,
                                        reason: reason,
                                        status: "open",
                                        raised-at-height: block-height,
                                        resolved-at-height: none,
                                        resolution: none,
                                        project-id-copy: validated-project-id,
                                        task-id-copy: validated-task-id
                                    }
                                )
                                ;; Lock the escrow
                                (match (map-get? task-escrow { project-id: validated-project-id, task-id: validated-task-id })
                                    escrow-info
                                        (map-set task-escrow
                                            { project-id: validated-project-id, task-id: validated-task-id }
                                            (merge escrow-info { is-locked: true })
                                        )
                                    true
                                )
                                (ok true)
                            )
                        )
                    ERR-TASK-NOT-FOUND
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

;; Resolves a dispute
;; Only project owner can resolve (future: can be extended to governance/arbitration)
;; resolution-type: "refund" returns funds to owner, "release" pays assignee
(define-public (resolve-dispute 
    (project-id uint) 
    (task-id uint) 
    (resolution-type (string-ascii 20))
    (resolution-note (string-ascii 500))
)
    (let
        (
            (caller tx-sender)
        )
        (match (map-get? projects { project-id: project-id })
            project-data
                (match (map-get? tasks { project-id: project-id, task-id: task-id })
                    task-data
                        (match (map-get? task-disputes { project-id: project-id, task-id: task-id })
                            dispute-data
                                (let
                                    (
                                        (validated-project-id (get project-id-copy dispute-data))
                                        (validated-task-id (get task-id-copy dispute-data))
                                    )
                                    (begin
                                        (asserts! (is-eq (get owner project-data) caller) ERR-UNAUTHORIZED-ACCESS)
                                        
                                        ;; Handle escrow based on resolution
                                        (match (map-get? task-escrow { project-id: validated-project-id, task-id: validated-task-id })
                                            escrow-info
                                                (if (is-eq resolution-type "release")
                                                    ;; Release funds to assignee
                                                    (try! (as-contract (stx-transfer? (get amount escrow-info) tx-sender (get assignee task-data))))
                                                    ;; Refund to project owner
                                                    (try! (as-contract (stx-transfer? (get amount escrow-info) tx-sender (get owner project-data))))
                                                )
                                            true
                                        )
                                        ;; Update dispute status
                                        (map-set task-disputes
                                            { project-id: validated-project-id, task-id: validated-task-id }
                                            (merge dispute-data {
                                                status: "resolved",
                                                resolved-at-height: (some block-height),
                                                resolution: (some resolution-note)
                                            })
                                        )
                                        ;; Clear escrow
                                        (map-delete task-escrow { project-id: validated-project-id, task-id: validated-task-id })
                                        (ok true)
                                    )
                                )
                            ERR-INVALID-INPUT
                        )
                    ERR-TASK-NOT-FOUND
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

;; Modified complete-task to work with escrow system
;; Releases funds from escrow instead of direct transfer
(define-public (complete-task-with-escrow (project-id uint) (task-id uint))
    (let
        (
            (caller tx-sender)
        )
        (match (map-get? projects { project-id: project-id })
            project-data
                (match (map-get? tasks { project-id: project-id, task-id: task-id })
                    task-data
                        (let
                            (
                                (validated-project-id (get project-id-copy task-data))
                                (validated-task-id (get task-id-copy task-data))
                            )
                            (begin
                                (asserts! (is-none (map-get? task-disputes { project-id: validated-project-id, task-id: validated-task-id })) ERR-INVALID-INPUT)
                                (asserts! (is-eq (get assignee task-data) caller) ERR-UNAUTHORIZED-ACCESS)
                                (asserts! (is-eq (get current-status task-data) "pending") ERR-UNAUTHORIZED-ACCESS)
                                
                                ;; Release funds from escrow
                                (match (map-get? task-escrow { project-id: validated-project-id, task-id: validated-task-id })
                                    escrow-info
                                        (try! (as-contract (stx-transfer? (get amount escrow-info) tx-sender caller)))
                                    (try! (stx-transfer? (get reward-amount task-data) (get owner project-data) caller))
                                )
                                ;; Update task status
                                (map-set tasks
                                    { project-id: validated-project-id, task-id: validated-task-id }
                                    (merge task-data { current-status: "completed" })
                                )
                                ;; Update member stats
                                (let ((current-stats (default-to
                                        { tasks-completed: u0, total-earned: u0, average-rating: u0, total-ratings: u0, member-address-copy: caller }
                                        (map-get? member-stats { member-address: caller })
                                    )))
                                    (map-set member-stats
                                        { member-address: caller }
                                        {
                                            tasks-completed: (+ (get tasks-completed current-stats) u1),
                                            total-earned: (+ (get total-earned current-stats) (get reward-amount task-data)),
                                            average-rating: (get average-rating current-stats),
                                            total-ratings: (get total-ratings current-stats),
                                            member-address-copy: caller
                                        }
                                    )
                                )
                                ;; Clear escrow
                                (map-delete task-escrow { project-id: validated-project-id, task-id: validated-task-id })
                                (ok true)
                            )
                        )
                    ERR-TASK-NOT-FOUND
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

;; Read-only functions for dispute system
(define-read-only (get-dispute-info (project-id uint) (task-id uint))
    (map-get? task-disputes { project-id: project-id, task-id: task-id })
)

(define-read-only (get-escrow-info (project-id uint) (task-id uint))
    (map-get? task-escrow { project-id: project-id, task-id: task-id })
)