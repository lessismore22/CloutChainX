;; Social Media Rewards Program Contract
;; Implements a decentralized rewards system for social media interactions with enhanced safety checks

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-reward (err u102))
(define-constant err-invalid-principal (err u103))
(define-constant err-already-banned (err u104))
(define-constant err-not-banned (err u105))
(define-constant err-daily-limit-exceeded (err u106))
(define-constant err-content-reported (err u107))

;; Token for rewards
(define-fungible-token rewards-token)

;; Store user activity and rewards
(define-map user-activity 
  { user: principal }
  {
    posts: uint,
    likes-given: uint,
    likes-received: uint,
    total-reward-points: uint
  }
)

;; Reward rates
(define-data-var post-reward-rate uint u10)
(define-data-var like-reward-rate uint u1)
(define-data-var interaction-multiplier uint u2)

;; Validate principal
(define-private (is-valid-principal (user principal))
  (and 
    (not (is-eq user contract-owner)) 
    (not (is-eq user tx-sender))
  )
)

;; Validate reward amount
(define-private (is-valid-reward-amount (amount uint))
  (and (> amount u0) (<= amount u1000))
)

;; Initialize user activity
(define-read-only (get-user-activity (user principal))
  (default-to 
    {
      posts: u0,
      likes-given: u0, 
      likes-received: u0,
      total-reward-points: u0
    }
    (map-get? user-activity { user: user })))

;; Record a new post
(define-public (record-post)
  (let 
    (
      (current-activity (get-user-activity tx-sender))
      (new-posts (+ (get posts current-activity) u1))
      (reward-points (+ (get total-reward-points current-activity) (var-get post-reward-rate)))
    )
    (map-set user-activity 
      { user: tx-sender }
      {
        posts: new-posts,
        likes-given: (get likes-given current-activity),
        likes-received: (get likes-received current-activity),
        total-reward-points: reward-points
      }
    )
    (ok true)
  )
)

;; Record a like interaction
(define-public (record-like (target principal))
  (begin
    ;; Validate target principal
    (asserts! (is-valid-principal target) (err err-invalid-principal))
    
    (let 
      (
        ;; Update like giver's activity
        (giver-activity (get-user-activity tx-sender))
        (new-likes-given (+ (get likes-given giver-activity) u1))
        
        ;; Update like receiver's activity
        (receiver-activity (get-user-activity target))
        (new-likes-received (+ (get likes-received receiver-activity) u1))
        (interaction-points (* (var-get like-reward-rate) (var-get interaction-multiplier)))
        (receiver-reward-points (+ (get total-reward-points receiver-activity) interaction-points))
      )
      ;; Update giver's activity
      (map-set user-activity 
        { user: tx-sender }
        {
          posts: (get posts giver-activity),
          likes-given: new-likes-given,
          likes-received: (get likes-received giver-activity),
          total-reward-points: (get total-reward-points giver-activity)
        }
      )
      
      ;; Update receiver's activity
      (map-set user-activity 
        { user: target }
        {
          posts: (get posts receiver-activity),
          likes-given: (get likes-given receiver-activity),
          likes-received: new-likes-received,
          total-reward-points: receiver-reward-points
        }
      )
      
      (ok true)
    )
  )
)

;; Withdraw rewards
(define-public (withdraw-rewards (amount uint))
  (let 
    (
      (balance (ft-get-balance rewards-token tx-sender))
    )
    (asserts! (>= balance amount) err-insufficient-balance)
    (try! (ft-transfer? rewards-token amount tx-sender contract-owner))
    (ok true)
  )
)

;; View total rewards earned by a user
(define-read-only (get-total-rewards (user principal))
  (ft-get-balance rewards-token user)
)

;; Initialize the contract
(define-private (initialize)
  (begin
    (var-set post-reward-rate u10)
    (var-set like-reward-rate u1)
    (var-set interaction-multiplier u2)
    true
  )
)

;; Run initialization on contract deploy
(initialize)

;; Banned users list
(define-map banned-users principal bool)

;; Content reporting system
(define-map reported-content 
  { 
    content-id: (string-ascii 100),
    reporter: principal 
  }
  {
    reasons: (list 3 (string-ascii 50)),
    report-count: uint
  }
)
(define-map daily-activity 
  { 
    user: principal, 
    date: uint 
  }
  {
    post-count: uint,
    like-count: uint
  }
)

;; Check and update daily activity limits
(define-private (check-daily-activity-limit (activity-type (string-ascii 10)))
  (let 
    (
      (current-block (get-current-block))
      (user-activity (get-user-activity tx-sender))
      (current-daily-activity   
        (default-to 
          { post-count: u0, like-count: u0 }
          (map-get? daily-activity 
            { 
              user: tx-sender, 
              date: current-block 
            })
        )
    )
    (if (is-eq activity-type "post")
      (begin
        (asserts! 
          (< 
            (get post-count current-daily-activity) 
            (var-get daily-post-limit)
          ) 
          (err err-daily-limit-exceeded)
        )
        (map-set daily-activity 
          { 
            user: tx-sender, 
            date: current-block 
          }
          {
            post-count: (+ (get post-count current-daily-activity) u1),
            like-count: (get like-count current-daily-activity)
          }
        )
        (ok true)
      )
      (begin
        (asserts! 
          (< 
            (get like-count current-daily-activity) 
            (var-get daily-like-limit)
          ) 
          (err err-daily-limit-exceeded)
        )
        (map-set daily-activity 
          { 
            user: tx-sender, 
            date: current-block 
          }
          {
            post-count: (get post-count current-daily-activity),
            like-count: (+ (get like-count current-daily-activity) u1)
          }
        )
        (ok true)
      )
    )
  )
  ;; New error codes
(define-constant err-invalid-comment (err u200))
(define-constant err-invalid-tag (err u201))
(define-constant err-invalid-share (err u202))
(define-constant err-insufficient-level (err u203))

;; Store comments data
(define-map comments
  { post-id: uint, commenter: principal }
  {
    content: (string-ascii 280),
    timestamp: uint,
    likes: uint
  }
)

;; Track user achievements
(define-map achievements
  principal
  {
    badges: (list 10 (string-ascii 50)),
    level: uint,
    experience: uint
  }
)
;; Store content categories/tags
(define-map content-tags
  uint
  (list 5 (string-ascii 20))
)

;; Track content sharing
(define-map shared-content
  { post-id: uint, sharer: principal }
  {
    original-poster: principal,
    share-timestamp: uint,
    reach: uint
  }
)
;; Record a comment
(define-public (add-comment (post-id uint) (content (string-ascii 280)))
  (let
    (
      (current-block (get-block-height))
    )
    (map-set comments
      { post-id: post-id, commenter: tx-sender }
      {
        content: content,
        timestamp: current-block,
        likes: u0
      }
    )
    (ok true)
  )
)

;; Add tags to content
(define-public (tag-content (post-id uint) (tags (list 5 (string-ascii 20))))
  (begin
    (map-set content-tags post-id tags)
    (ok true)
  )
)

;; Share content
(define-public (share-post (post-id uint) (original-poster principal))
  (let
    (
      (current-block (get-block-height))
    )
    (map-set shared-content
      { post-id: post-id, sharer: tx-sender }
      {
        original-poster: original-poster,
        share-timestamp: current-block,
        reach: u0
      }
    )
    (ok true)
  )
)
;; Award achievement badge
(define-public (award-badge (user principal) (badge (string-ascii 50)))
  (let
    (
      (current-achievements (default-to 
        { badges: (list), level: u0, experience: u0 }
        (map-get? achievements user)))
    )
    (map-set achievements
      user
      (merge current-achievements {
        badges: (unwrap! (as-max-len? (append (get badges current-achievements) badge) u10) (err u1))
      })
    )
    (ok true)
  )
)

;; Read-only functions for new features
(define-read-only (get-post-comments (post-id uint))
  (map-get? comments { post-id: post-id, commenter: tx-sender })
)

(define-read-only (get-post-tags (post-id uint))
  (map-get? content-tags post-id)
)

(define-read-only (get-user-achievements (user principal))
  (map-get? achievements user)
)

(define-read-only (get-share-stats (post-id uint))
  (map-get? shared-content { post-id: post-id, sharer: tx-sender })
)
))
;; Track votes on reported content
(define-map content-votes
  { content-id: (string-ascii 100) }
  {
    upvotes: uint,
    downvotes: uint
  }
)

;; Threshold for content removal
(define-data-var content-removal-threshold uint u10)

;; Vote on reported content
(define-public (vote-on-content (content-id (string-ascii 100)) (vote (string-ascii 10)))
  (begin
    ;; Ensure the content is reported
    (asserts! (is-some (map-get? reported-content { content-id: content-id, reporter: tx-sender })) (err err-content-reported))
    
    ;; Update vote counts
    (let 
      (
        (current-votes (default-to { upvotes: u0, downvotes: u0 } (map-get? content-votes { content-id: content-id })))
      )
      (if (is-eq vote "upvote")
        (map-set content-votes 
          { content-id: content-id }
          { 
            upvotes: (+ (get upvotes current-votes) u1),
            downvotes: (get downvotes current-votes)
          }
        )
        (map-set content-votes 
          { content-id: content-id }
          { 
            upvotes: (get upvotes current-votes),
            downvotes: (+ (get downvotes current-votes) u1)
          }
        )
      )
    )
    (ok true)
  )
)

;; Check if content should be removed
(define-public (check-content-removal (content-id (string-ascii 100)))
  (let 
    (
      (current-votes (default-to { upvotes: u0, downvotes: u0 } (map-get? content-votes { content-id: content-id })))
    )
    (if (>= (get downvotes current-votes) (var-get content-removal-threshold))
      (ok true) ;; Content should be removed
      (ok false) ;; Content should not be removed
    )
  )

;; Track user levels and experience
(define-map user-levels
  principal
  {
    level: uint,
    experience: uint
  }
)

;; XP required for each level
(define-data-var xp-per-level uint u100)

;; Award XP for user activity
(define-private (award-xp (user principal) (xp uint))
  (let 
    (
      (current-level (default-to { level: u1, experience: u0 } (map-get? user-levels user)))
      (new-experience (+ (get experience current-level) xp))
      (new-level (if (>= new-experience (var-get xp-per-level))
                   (+ (get level current-level) u1)
                   (get level current-level)
                 ))
    )
    (map-set user-levels 
      user
      {
        level: new-level,
        experience: new-experience
      }
    )
    (ok true)
  )
)

;; Update XP in existing functions
;; Example: Add to `record-post`
(define-public (record-post)
  (let 
    (
      (current-activity (get-user-activity tx-sender))
      (new-posts (+ (get posts current-activity) u1))
      (reward-points (+ (get total-reward-points current-activity) (var-get post-reward-rate)))
    )
    (map-set user-activity 
      { user: tx-sender }
      {
        posts: new-posts,
        likes-given: (get likes-given current-activity),
        likes-received: (get likes-received current-activity),
        total-reward-points: reward-points
      }
    )
    (try! (award-xp tx-sender u10)) ;; Award 10 XP for posting
    (ok true)
  )
)
;; Track leaderboard rankings
(define-map leaderboard
  uint ;; Rank
  principal ;; User
)

;; Update leaderboard
(define-private (update-leaderboard (user principal))
  (let 
    (
      (user-stats (get-user-activity user))
      (total-points (get total-reward-points user-stats))
    )
    ;; Logic to update leaderboard based on total points
    ;; (This can be expanded with more complex ranking logic)
    (map-set leaderboard total-points user)
    (ok true)
  )
)

;; Get top users
(define-read-only (get-top-users (limit uint))
  (let 
    (
      (top-users (map-get? leaderboard limit))
    )
    top-users
  )
)
)
