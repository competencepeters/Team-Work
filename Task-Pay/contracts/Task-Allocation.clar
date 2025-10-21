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
        members: (list 20 principal)
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
        created-at-height: uint
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
        total-ratings: uint
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
        (err ERR-PROJECT-NOT-FOUND)
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
                        members: (list)
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
            project-info
                (if (is-eq (get owner project-info) caller)
                    (if (is-some (index-of (get members project-info) member-address))
                        ERR-INVALID-INPUT
                        (begin
                            (map-set projects
                                { project-id: project-id }
                                (merge project-info { members: (unwrap! (as-max-len? (append (get members project-info) member-address) u20) ERR-UNAUTHORIZED-ACCESS) })
                            )
                            (ok true)
                        )
                    )
                    ERR-UNAUTHORIZED-ACCESS
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
            project-info
                (if (is-eq (get owner project-info) caller)
                    (if (and 
                            (> (len title) u0)
                            (> (len description) u0)
                            (> deadline block-height)
                            (> reward u0)
                            (or
                                (is-eq assignee (get owner project-info))
                                (is-some (index-of (get members project-info) assignee))
                            )
                        )
                        (match (get-next-task-id project-id)
                            new-task-id
                                (begin
                                    (map-set tasks
                                        { project-id: project-id, task-id: new-task-id }
                                        {
                                            assignee: assignee,
                                            title: title,
                                            description: description,
                                            deadline-height: deadline,
                                            reward-amount: reward,
                                            current-status: "pending",
                                            created-at-height: block-height
                                        }
                                    )
                                    (ok new-task-id)
                                )
                            error ERR-PROJECT-NOT-FOUND
                        )
                        ERR-INVALID-INPUT
                    )
                    ERR-UNAUTHORIZED-ACCESS
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
            project-info
                (match (map-get? tasks { project-id: project-id, task-id: task-id })
                    task-info
                        (if (or (is-eq (get owner project-info) caller) (is-eq (get assignee task-info) caller))
                            (if (> (len new-status) u0)
                                (begin
                                    (map-set tasks
                                        { project-id: project-id, task-id: task-id }
                                        (merge task-info { current-status: new-status })
                                    )
                                    (ok true)
                                )
                                ERR-INVALID-INPUT
                            )
                            ERR-UNAUTHORIZED-ACCESS
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
            project-info
                (match (map-get? tasks { project-id: project-id, task-id: task-id })
                    task-info
                        (if (and
                                (is-eq (get assignee task-info) caller)
                                (is-eq (get current-status task-info) "pending")
                            )
                            (begin
                                (try! (stx-transfer? (get reward-amount task-info) (get owner project-info) caller))
                                (map-set tasks
                                    { project-id: project-id, task-id: task-id }
                                    (merge task-info { current-status: "completed" })
                                )
                                (let ((current-stats (default-to
                                        { tasks-completed: u0, total-earned: u0, average-rating: u0, total-ratings: u0 }
                                        (map-get? member-stats { member-address: caller })
                                    )))
                                    (map-set member-stats
                                        { member-address: caller }
                                        {
                                            tasks-completed: (+ (get tasks-completed current-stats) u1),
                                            total-earned: (+ (get total-earned current-stats) (get reward-amount task-info)),
                                            average-rating: (get average-rating current-stats),
                                            total-ratings: (get total-ratings current-stats)
                                        }
                                    )
                                )
                                (ok true)
                            )
                            ERR-UNAUTHORIZED-ACCESS
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
    (if (and 
            (>= rating u1) 
            (<= rating u5)
        )
        (let
            (
                (current-stats (default-to
                    { tasks-completed: u0, total-earned: u0, average-rating: u0, total-ratings: u0 }
                    (map-get? member-stats { member-address: member })
                ))
            )
            (map-set member-stats
                { member-address: member }
                {
                    tasks-completed: (get tasks-completed current-stats),
                    total-earned: (get total-earned current-stats),
                    average-rating: (/ (+ (* (get average-rating current-stats) (get total-ratings current-stats)) rating) (+ (get total-ratings current-stats) u1)),
                    total-ratings: (+ (get total-ratings current-stats) u1)
                }
            )
            (ok true)
        )
        ERR-INVALID-INPUT
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