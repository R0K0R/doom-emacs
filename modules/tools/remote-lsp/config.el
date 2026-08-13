;;; tools/remote-lsp/config.el -*- lexical-binding: t; -*-
;;
;; Makes LSP survive over TRAMP. Three independent upstream defects, all found
;; by tracing a single failure: opening a Python file on a remote host produced
;; "tramp_stat_file_attributes ... does not return a valid Lisp expression",
;; then a flood of `listp'/`stringp' errors, then a multi-minute 94% CPU freeze.
;;
;; Each fix is documented at its own definition below. All three are
;; upstream-reportable (Emacs' bundled TRAMP, and lsp-mode) rather than
;; peculiarities of this config.

;;; ------------------------------------------------------------------
;;; 1. TRAMP: idle-timer reentrancy on a shared connection
;;; ------------------------------------------------------------------
;; TRAMP's shell protocol is strictly sequential: a command must consume its own
;; end-of-command sentinel before the next is sent on that connection. TRAMP
;; guards this with `with-tramp-locked-connection' -- but that only wraps
;; `tramp-accept-process-output', so the lock is taken and RELEASED on every
;; iteration of `tramp-wait-for-regexp's loop, which yields between them:
;;
;;     (while (not found)
;;       (sit-for 0 'nodisp)                ; outside lock AND timer suspension
;;       (tramp-accept-process-output proc)  ; locked, timers suspended
;;       ...)
;;
;; `sit-for' runs pending timers (via its `input-pending-p' check). So a timer
;; touching the same connection can send a second command mid-flight -- and
;; because the lock genuinely is not held at that instant, TRAMP's own
;; "Forbidden reentrant call of Tramp" check never fires. Both reads then
;; consume each other's output and the stream stays misaligned for every later
;; command, surfacing as garbage parsed as Lisp.
;;
;; Must be IDLE-only: `tramp-wait-for-regexp' wraps its loop in
;; `with-tramp-timeout', whose escape hatch is a REGULAR timer, so binding
;; `timer-list' too (as `with-tramp-suspended-timers' does) makes a wait whose
;; regexp never arrives spin forever. Measured:
;;   (let (timer-idle-list) ...)            -> regular fires, idle blocked
;;   (let (timer-list timer-idle-list) ...) -> regular blocked  (hangs Emacs)
;; Sufficient because the reentrancy source is idle-scheduled: lsp-mode's
;; `(run-with-idle-timer 0 nil ...)' around `lsp--init-if-visible'.
;; Idle timers are deferred, never dropped.
(defadvice! +remote-lsp--tramp-no-idle-timers-a (fn &rest args)
  "Close TRAMP's idle-timer reentrancy window in `tramp-wait-for-regexp'."
  :around #'tramp-wait-for-regexp
  (let (timer-idle-list)
    (apply fn args)))


;;; ------------------------------------------------------------------
;;; 2. lsp-mode: client-packages guard set too late
;;; ------------------------------------------------------------------
;; `lsp--require-packages' sets its "already loaded" flag only AFTER walking
;; `lsp-client-packages'. Loading a client can block -- lsp-pyright's `after!'
;; block resolves a binary, which over TRAMP is a remote round-trip -- and while
;; it blocks the flag is still nil, so a re-entrant call (idle timer ->
;; `lsp--init-if-visible' -> `lsp') re-walks the ENTIRE ~100-package client list
;; from the top. That is what turns one TRAMP reentrancy (above) into dozens of
;; racing remote probes. Setting the flag first makes the guard actually guard;
;; the loop body is otherwise verbatim upstream.
(defadvice! +remote-lsp--require-packages-guard-first-a ()
  "Set lsp-mode's client-packages guard BEFORE loading, not after."
  :override #'lsp--require-packages
  (when (and lsp-auto-configure (not lsp--client-packages-required))
    (setq lsp--client-packages-required t)
    (seq-do (lambda (package)
              ;; loading client is slow and `lsp' can be called repeatedly
              (unless (featurep package)
                (require package nil t)))
            lsp-client-packages)))


;;; ------------------------------------------------------------------
;;; 3. lsp-mode: unbounded file-watch tree walk
;;; ------------------------------------------------------------------
;; `lsp-watch-root-folder' calls `lsp--all-watchable-directories', which walks
;; the entire tree doing `file-accessible-directory-p' + `file-symlink-p' per
;; ENTRY -- and does so BEFORE `lsp-file-watch-threshold' is consulted, so that
;; threshold caps how many watchers get ADDED but never prevents the walk that
;; costs the time. Over TRAMP each stat is a remote round-trip: measured ~30ms
;; per entry, i.e. ~68 minutes of pinned CPU for a 137k-file project.
;;
;; The same information comes from ONE `process-file' -- which TRAMP runs as a
;; single remote command -- in 1.79s for that same tree, ~2300x cheaper. Use it
;; to decide whether the real walk may run at all. Excluding a large output
;; directory brings the count back under the limit and watchers resume on their
;; own, so this is never a permanent opt-out.

(defvar +remote-lsp-watch-max-entries 5000
  "Skip LSP file watchers when a project tree exceeds this many files.
Counted AFTER the workspace's ignored-directory regexes, so excluding a
large output directory brings a project back under the limit.")

(defvar +remote-lsp--watch-counts-cache (make-hash-table :test 'equal))

(defun +remote-lsp-watch-top-level-counts (root &optional force)
  "Return ((NAME . FILE-COUNT) ...) for ROOT's children, sorted descending."
  (let ((key (file-truename (file-name-as-directory root))))
    (or (and (not force) (gethash key +remote-lsp--watch-counts-cache))
        (puthash
         key
         (let ((default-directory (file-name-as-directory root))
               (counts (make-hash-table :test 'equal)))
           (with-temp-buffer
             (unless (zerop (process-file
                             "sh" nil t nil "-c"
                             "find . -type f -printf '%h\\n' 2>/dev/null | sort | uniq -c"))
               (user-error "remote-lsp: could not enumerate %s" root))
             (goto-char (point-min))
             (while (re-search-forward "^ *\\([0-9]+\\) +\\(.*\\)$" nil t)
               (let* ((n (string-to-number (match-string 1)))
                      (rel (replace-regexp-in-string "\\`\\./" "" (match-string 2)))
                      (top (if (or (string= rel ".") (string= rel ""))
                               "."
                             (car (split-string rel "/")))))
                 (puthash top (+ n (gethash top counts 0)) counts))))
           (sort (let (acc) (maphash (lambda (k v) (push (cons k v) acc)) counts) acc)
                 (lambda (a b) (> (cdr a) (cdr b)))))
         +remote-lsp--watch-counts-cache))))

(defun +remote-lsp-watch-dir-regexp (name)
  "Regexp for `lsp-file-watch-ignored-directories' matching a dir called NAME."
  (concat "[/\\\\]" (regexp-quote name) "\\'"))

(defun +remote-lsp-watch-effective-count (root ignored-directories)
  "Total files under ROOT, excluding children matching IGNORED-DIRECTORIES."
  (cl-loop for (name . n) in (+remote-lsp-watch-top-level-counts root)
           unless (or (string= name ".")
                      (lsp--string-match-any
                       ignored-directories (expand-file-name name root)))
           sum n))

;;;###autoload
(defun +remote-lsp/pick-watch-exclusions (&optional root)
  "Choose directories to exclude from LSP file watching, and persist them.

Lists ROOT's children by recursive file count and writes the selection to
ROOT's `.dir-locals.el' as `lsp-file-watch-ignored-directories', which
lsp-mode reads per workspace root (see
`lsp--get-ignored-regexes-for-workspace-root') and which is registered
`safe-local-variable', so it applies without prompting.

This is what `lsp--ask-about-watching-big-repo' should be: it says WHAT is
big, and it remembers the answer -- rather than asking a blind yes/no after
the expensive walk has already happened."
  (interactive)
  (let* ((root (file-name-as-directory
                (or root (lsp-workspace-root) default-directory)))
         (counts (cl-remove-if (lambda (c) (string= (car c) "."))
                               (+remote-lsp-watch-top-level-counts root t)))
         (_ (unless counts (user-error "No subdirectories with files under %s" root)))
         (display->name (make-hash-table :test 'equal))
         (cands (mapcar (lambda (c)
                          (let ((s (format "%-32s %9d files" (car c) (cdr c))))
                            (puthash s (car c) display->name)
                            s))
                        counts))
         (picked (completing-read-multiple
                  (format "Exclude from watching (total %d files, limit %d): "
                          (cl-reduce #'+ counts :key #'cdr :initial-value 0)
                          +remote-lsp-watch-max-entries)
                  cands nil t))
         (names (delq nil (mapcar (lambda (s) (gethash s display->name)) picked))))
    (unless names (user-error "Nothing selected"))
    (let* ((new (mapcar #'+remote-lsp-watch-dir-regexp names))
           ;; dir-locals SETS the variable, so carry the global defaults along
           ;; or .git/node_modules/etc. would be silently dropped.
           (value (cl-remove-duplicates
                   (append (default-value 'lsp-file-watch-ignored-directories) new)
                   :test #'equal))
           (default-directory root)
           (enable-remote-dir-locals t))
      (add-dir-local-variable nil 'lsp-file-watch-ignored-directories value)
      (when-let ((buf (get-file-buffer (expand-file-name ".dir-locals.el" root))))
        (with-current-buffer buf (save-buffer)))
      (remhash (file-truename root) +remote-lsp--watch-counts-cache)
      (message "Excluded %s -- restart the workspace to apply"
               (string-join names ", ")))))

;; IGNORED-DIRECTORIES here is the argument lsp-mode already computed via
;; `lsp--get-ignored-regexes-for-workspace-root', so it is dir-locals-aware:
;; whatever the picker wrote is honoured on the very next check.
(defadvice! +remote-lsp--watch-guard-big-tree-a (fn dir callback ignored-files
                                                    ignored-directories
                                                    &optional watch warn-big-repo?)
  "Refuse the O(tree) watch walk when a cheap count says it is pathological."
  :around #'lsp-watch-root-folder
  (let ((n (condition-case err
               (+remote-lsp-watch-effective-count dir ignored-directories)
             (error (lsp-log "remote-lsp: count failed (%s); allowing walk"
                             (error-message-string err))
                    0))))
    (if (> n +remote-lsp-watch-max-entries)
        (progn
          (lsp--warn "Skipping file watchers for %s: %d files after exclusions (limit %d). \
Run `M-x +remote-lsp/pick-watch-exclusions' to exclude large directories."
                     dir n +remote-lsp-watch-max-entries)
          (or watch (make-lsp-watch :root-directory dir)))
      (funcall fn dir callback ignored-files ignored-directories watch warn-big-repo?))))

;; Without this a `.dir-locals.el' in a REMOTE project root is ignored outright
;; (the default is nil), and everything the picker writes silently does nothing.
(setq enable-remote-dir-locals t)


;;; ------------------------------------------------------------------
;;; 3b. No file-notify watches on remote paths, for ANY package
;;; ------------------------------------------------------------------
;; The guard above only covers lsp-mode. Treemacs hits the same wall
;; independently: `treemacs-filewatch-mode' watches every directory it
;; displays, and over TRAMP each watch is a separate remote `gio monitor' (or
;; `inotifywait') PROCESS. Showing the yulee project opened 49 of them and
;; pinned a core at 95% until the mode was turned off -- measured, 0.0% after.
;;
;; This is inherent to remote file notification, not specific to either
;; package, so guard at the one choke point they share. Refusing with
;; `file-notify-error' rather than returning nil is deliberate: it is the error
;; `file-notify-add-watch' already signals when watching is unsupported, so
;; callers handle it. Treemacs in particular wraps its call in
;;   (treemacs-with-ignored-errors
;;     ((file-notify-error "No file notification program found")) ...)
;; which matches on that message and silently skips -- so keep the wording.
;;
;; Cost of doing this: changes made outside Emacs on the remote are not
;; auto-detected (no auto-revert, no Treemacs auto-refresh there). Your own
;; edits are unaffected. Set to nil to opt back in.
(defvar +remote-lsp-inhibit-remote-file-watches t
  "When non-nil, refuse `file-notify-add-watch' on remote (TRAMP) paths.")

(defadvice! +remote-lsp--no-remote-file-notify-a (fn file &rest args)
  "Refuse remote file-notify watches; each one is a remote process."
  :around #'file-notify-add-watch
  (if (and +remote-lsp-inhibit-remote-file-watches
           (file-remote-p file))
      (signal 'file-notify-error
              (list "No file notification program found" file))
    (apply fn file args)))


;;; ------------------------------------------------------------------
;;; 4. pyright vs basedpyright: decide per host, not once at load
;;; ------------------------------------------------------------------
;; lsp-pyright registers exactly two clients, `pyright' and `pyright-remote';
;; there is no basedpyright client. Which BINARY they run comes from
;; `lsp-pyright-langserver-command', so picking the flavour is a per-host
;; question -- and the hosts genuinely disagree:
;;
;;   laptop            basedpyright only
;;   yulee (plain)     pyright only
;;   qas-dev container basedpyright only
;;
;; Deciding once at load time (whatever host happened to be current when
;; lsp-pyright loaded) is therefore wrong for every other host, and shows up as
;; "servers support current file but do not have automatic installation".
;;
;; Both resolution paths can be made dynamic:
;;   - `pyright-remote' builds its command in a lambda at connect time, so a
;;     buffer-local `lsp-pyright-langserver-command' is honoured.
;;   - the local `pyright' client goes through `lsp-package-path' -> the
;;     :system provider -> `lsp--system-path', which calls `lsp-resolve-value'
;;     on its argument and then `executable-find' with REMOTE=t. So a lambda
;;     works there and is evaluated against the right host.

(defvar +remote-lsp--pyright-flavor-cache (make-hash-table :test 'equal)
  "Cache of TRAMP-prefix -> \"basedpyright\"/\"pyright\".
Keyed by `file-remote-p' so each host/container is probed once.")

(defun +remote-lsp-pyright-flavor ()
  "Return whichever pyright flavour exists on the current buffer's host.
Probes via `executable-find' with REMOTE=t, so it works for local files,
plain SSH, and multi-hop container paths like /ssh:host|docker:name: alike."
  (let* ((host (or (file-remote-p default-directory) "local"))
         (cached (gethash host +remote-lsp--pyright-flavor-cache)))
    (or cached
        (puthash host
                 (cond ((executable-find "basedpyright-langserver" t) "basedpyright")
                       ((executable-find "pyright-langserver" t) "pyright")
                       ;; Neither present: keep basedpyright so lsp reports a
                       ;; missing server rather than silently picking a flavour.
                       (t "basedpyright"))
                 +remote-lsp--pyright-flavor-cache))))

;;;###autoload
(defun +remote-lsp/clear-pyright-flavor-cache ()
  "Forget probed pyright flavours (after installing a server on a host)."
  (interactive)
  (clrhash +remote-lsp--pyright-flavor-cache)
  (message "remote-lsp: pyright flavour cache cleared"))

(after! lsp-pyright
  (setq lsp-pyright-type-checking-mode "standard")
  ;; Lambda, not a string: re-resolved per connection on the correct host.
  (lsp-dependency 'pyright
                  (list :system (lambda ()
                                  (concat (+remote-lsp-pyright-flavor) "-langserver"))))
  (add-hook! '(python-mode-hook python-ts-mode-hook)
    (defun +remote-lsp--pyright-flavor-h ()
      (setq-local lsp-pyright-langserver-command (+remote-lsp-pyright-flavor)))))

;; A mode hook alone is NOT enough. Buffers restored by
;; `doom/quickload-session' (and anything else that sets the major mode without
;; running its hooks) never get the buffer-local value, so lsp falls back to the
;; global default -- "pyright", which does not exist in the container -- and
;; reports "servers support current file but do not have automatic
;; installation". Observed on a freshly started daemon with the hooks correctly
;; installed, the flavour cache correct, and the probe working: the restored
;; buffer still had local?=nil, val="pyright".
;;
;; `lsp' and `lsp-deferred' both run in the buffer before client selection, so
;; setting it there catches every buffer regardless of how its mode was set.
(defadvice! +remote-lsp--set-pyright-flavor-a (&rest _)
  "Resolve the pyright flavour for this buffer's host before lsp picks a client."
  :before '(lsp lsp-deferred)
  (when (and (derived-mode-p 'python-mode 'python-ts-mode)
             (fboundp '+remote-lsp-pyright-flavor))
    (setq-local lsp-pyright-langserver-command (+remote-lsp-pyright-flavor))))
