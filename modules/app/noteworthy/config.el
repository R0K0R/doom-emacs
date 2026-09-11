;;; app/noteworthy/config.el -*- lexical-binding: t; -*-

(require 'noteworthy)

(defvar +noteworthy-terminal-cmd (list (or (executable-find "fish") shell-file-name))
  "Command to run in the Noteworthy terminal.")

(use-package! dtrt-indent
  :after typst-ts-mode
  :config
  ;; 1. Enable dtrt-indent whenever typst-ts-mode starts
  (add-hook 'typst-ts-mode-hook #'dtrt-indent-mode)
  
  ;; 2. (Optional) Help dtrt-indent recognize Typst syntax
  ;; Mapping it to 'javascript' usually works well for braces {} and brackets []
  (add-to-list 'dtrt-indent-hook-mapping-list '(typst-ts-mode javascript)))

;; typst grammar comes from Nix (treesit-grammars.with-all-grammars, see
;; config.el's TREESIT_GRAMMAR_DIR wiring) -- no install-time source needed.

(use-package! typst-preview
  :config
  (setq typst-preview-executable "tinymist")
  (setq typst-preview-partial-rendering t))

;; Register Typst language ID so lsp-mode can route .typ buffers to Tinymist
(after! lsp-mode
  (add-to-list 'lsp-language-id-configuration '(typst-ts-mode . "typst")))

;; lsp-mode runs tinymist ON the project host, so the binary has to be on the
;; PATH that TRAMP builds.  TRAMP's sshx method runs /bin/sh there, but the
;; shell is not the point: on this host nix is installed per-user and is not
;; wired into the system profile, so neither the login shell nor `/bin/sh -lc'
;; puts ~/.nix-profile/bin on PATH -- `command -v tinymist' under either comes
;; back empty.  `tramp-own-remote-path' therefore misses it, and lsp-mode
;; reports "servers support current file but do not have automatic
;; installation: tinymist-tramp".  Name the profile directory explicitly.
(after! tramp
  (add-to-list 'tramp-remote-path "/home/r0k0r/.nix-profile/bin")
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

;; Getting the chapter/page inputs into tinymist took four separate fixes, so
;; they are all recorded here:
;;
;;  1. lsp-mode ships clients/lsp-typst.el, which registers :server-id
;;     'tinymist with NO :initialization-options.  Last registration wins, and
;;     registering a non-remote client regenerates the -tramp clone from it --
;;     so if that file loads after us, our options are replaced by nil.  Load
;;     it FIRST, then register over it.
;;  2. A TRAMP buffer uses the auto-generated `tinymist-tramp' clone, and
;;     `lsp-auto-register-remote-clients' does not re-run when `tinymist' is
;;     re-registered.  Register the remote client by hand too.
;;  3. tinymist's typstExtraArgs is a string[], one flag per element using `=':
;;     ["--input=k=v", ...].  A single space-joined string is ignored.
;;  4. `noteworthy-collab-typst-inputs' reads the project with ordinary file
;;     operations -- over TRAMP that is a TRAMP call, and
;;     `lsp--start-workspace' is already inside one.  The reentrant call errors
;;     and is swallowed, leaving inputs: {} at initialize.  Compute in the mode
;;     hook instead and cache it -- in the package, so that the commands which
;;     change the structure can invalidate the same cache initialize reads.

(defun +noteworthy-typst-root ()
  "Project root for this buffer, however the session was started.
`lsp-deferred' can fire before `noteworthy-collab--project-root' is set."
  (or (bound-and-true-p noteworthy-collab--project-root)
      (bound-and-true-p noteworthy-project-root)
      (when default-directory
        (when-let* ((d (locate-dominating-file default-directory "noteworthy.py")))
          (expand-file-name d)))
      default-directory))

(defun +noteworthy-typst-inputs-for (root &optional force)
  "--input=k=v flags for ROOT, from the package's cache.
The cache lives in noteworthy-collab so that the things which change the
structure -- `noteworthy-collab-preview-start',
`noteworthy-collab-reload-structure' -- can invalidate it.  A second copy
here would go stale behind them and get re-sent at the next initialize,
which is the whole failure the restart exists to fix.  With FORCE, rescan."
  (let ((pairs (cond ((fboundp 'noteworthy-collab-typst-inputs-cached)
                      (noteworthy-collab-typst-inputs-cached root force))
                     ((fboundp 'noteworthy-collab-typst-inputs)
                      (ignore-errors (noteworthy-collab-typst-inputs root)))))
        (args nil))
    (while pairs
      (if (and (equal (car pairs) "--input") (cadr pairs))
          (progn (push (concat "--input=" (cadr pairs)) args)
                 (setq pairs (cddr pairs)))
        (push (car pairs) args)
        (setq pairs (cdr pairs))))
    (nreverse args)))

(defun +noteworthy-tinymist-init-options ()
  "rootPath and the Typst inputs, as tinymist reads them at initialize."
  (let* ((root (+noteworthy-typst-root))
         (remote-root (or (file-remote-p root 'localname) root))
         (args (+noteworthy-typst-inputs-for root)))
    (append (list :rootPath (directory-file-name remote-root))
            ;; exportOpts kept from the earlier registration this replaced.
            (when-let* ((main (or (bound-and-true-p noteworthy-collab-master-file)
                                  (bound-and-true-p noteworthy-master-file))))
              (list :exportOpts (list :input (or (file-remote-p main 'localname) main))))
            (when args (list :typstExtraArgs (vconcat args))))))

(defun +noteworthy-set-typst-extra-args ()
  "Warm the input cache and point `lsp-typst-extra-args' at it.
Runs from the mode hook -- outside the TRAMP call `lsp--start-workspace'
makes, which is the only place the project can be read safely."
  (when (boundp 'lsp-typst-extra-args)
    (let* ((root (+noteworthy-typst-root))
           (args (and root (+noteworthy-typst-inputs-for root t))))
      (when args (setq lsp-typst-extra-args (vconcat args))))))

;; Depth -50: this has to have run before `lsp-deferred' starts the server.
(add-hook 'typst-ts-mode-hook #'+noteworthy-set-typst-extra-args -50)

(after! lsp-mode
  (require 'lsp-typst nil t)            ; see (1) above -- must load first
  (dolist (remote '(nil t))
    (lsp-register-client
     (make-lsp-client
      :new-connection (if remote
                          (lsp-tramp-connection (lambda () (list "tinymist" "lsp")))
                        (lsp-stdio-connection (lambda () (list "tinymist" "lsp"))))
      :major-modes '(typst-ts-mode)
      :server-id (if remote 'tinymist-tramp 'tinymist)
      :remote? remote
      :priority 2
      :notification-handlers (lsp-ht ("tinymist/documentOutline" #'ignore)
                                     ("tinymist/documentMetrics" #'ignore)
                                     ("tinymist/preview/scrollSource" #'ignore))
      :initialization-options #'+noteworthy-tinymist-init-options))))

;;;###autoload
(defun noteworthy-collab-calculus2 ()
  "Open the Calculus II collab session on yulee."
  (interactive)
  (noteworthy-remote-init "ws://yulee:8011/ws/emacs"
                          "/sshx:yulee:/home/r0k0r/calculus_2"
                          (expand-file-name "~/KSA/Stewart_Calculus.pdf")))

;; Start LSP automatically in Typst files
(add-hook 'typst-ts-mode-hook #'lsp-deferred)

;; Ensure Flycheck uses LSP diagnostics (not naive CLI checkers)
(after! lsp-mode
  (setq lsp-diagnostics-provider :flycheck))

(defun +noteworthy-lsp-force-binary-coding ()
  "Put a remote language server's pipe back to binary.

`lsp-stdio-connection' asks for `:coding no-conversion' on purpose:
`lsp--parser-read' measures Content-Length in bytes, slices the body with
those byte counts, and decodes it itself with `decode-coding-region'.

Over TRAMP that request is ignored.  `tramp-sh' picks utf-8 whenever the
remote locale is UTF-8 -- its own comment reads "CCC this can't be the
right way to do it" -- so the filter is handed characters instead of
bytes.  Byte counts and character indices agree while the payload is
ASCII and part company the moment it is not, and tinymist's completions
are mostly math glyphs: a 128410-byte body arrived as ~127374 characters,
`substring' cut it short, and the parse died with json-end-of-file.

Forcing binary restores what lsp-mode already expects -- it is not a
second decode, it is declining TRAMP's."
  (when-let* ((ws (bound-and-true-p lsp--cur-workspace))
              (proc (lsp--workspace-cmd-proc ws)))
    ;; No remoteness guard.  The hook runs in whatever buffer happens to be
    ;; current, so `default-directory' is not reliably the project's -- and
    ;; the check is pointless anyway: `lsp-stdio-connection' asks for
    ;; no-conversion on every connection, so a local process is already
    ;; binary and setting it again changes nothing.
    (when (and (processp proc) (process-live-p proc))
      (set-process-coding-system proc 'binary 'binary))))

(add-hook 'lsp-after-initialize-hook #'+noteworthy-lsp-force-binary-coding)

(defun +noteworthy-tinymist-pin-main ()
  "Compile the whole book, not whichever file happens to be focused.

tinymist treats each opened file as its own document by default.  A content
page compiled that way never sees `#show ref: xref-rule' -- that lives in
parser.typ -- so every cross-reference in it is a hard error, and a document
that does not compile offers no labels to complete or jump to.  Pinned to
the master file the book is one document: references resolve, and `@'
completes labels from every page rather than from none.

Sent after initialize rather than as an initialization option: tinymist
takes the pin as a workspace command, and the path has to be the one the
server sees, which over TRAMP is the remote name without the method."
  (when-let* ((ws (bound-and-true-p lsp--cur-workspace))
              (id (lsp--client-server-id (lsp--workspace-client ws)))
              ((memq id '(tinymist tinymist-tramp)))
              (main (or (bound-and-true-p noteworthy-collab-master-file)
                        (bound-and-true-p noteworthy-master-file)))
              (path (or (file-remote-p main 'localname) main)))
    (with-lsp-workspace ws
      ;; Asynchronous on purpose: this runs inside initialize, and a
      ;; synchronous round trip there deadlocks against the server still
      ;; finishing its own startup.
      (lsp-request-async "workspace/executeCommand"
                         (list :command "tinymist.pinMain"
                               :arguments (vector path))
                         #'ignore
                         :error-handler #'ignore
                         :mode 'detached))))

(add-hook 'lsp-after-initialize-hook #'+noteworthy-tinymist-pin-main)

;; lsp-ui settings
(after! lsp-ui
  (setq lsp-ui-sideline-enable t
        lsp-ui-doc-enable t
        lsp-ui-doc-show-with-cursor nil))


;; Corfu auto-completion settings
(after! corfu
  (setq corfu-auto t)
  (setq corfu-auto-delay 0.1)
  (setq corfu-auto-prefix 1)
  (setq corfu-cycle t)
  (setq corfu-preselect 'first)
  ;; Disable preview/highlighting of completion candidate
  (setq corfu-preview-current nil))

;; Explicitly enable corfu-mode in Typst buffers
(add-hook 'typst-ts-mode-hook #'corfu-mode)

;; Smartparens for parenthesis/bracket pairing
(add-hook 'typst-ts-mode-hook #'smartparens-mode)

(after! smartparens
  (sp-with-modes 'typst-ts-mode
    ;; Ensure ( [ { always pair, even inside $ math mode or next to symbols
    (sp-local-pair "(" ")" :unless nil :actions '(insert wrap autoskip navigate))
    (sp-local-pair "[" "]" :unless nil :actions '(insert wrap autoskip navigate))
    (sp-local-pair "{" "}" :unless nil :actions '(insert wrap autoskip navigate))
    ;; Also pair $ for math mode
    (sp-local-pair "$" "$" :actions '(insert wrap autoskip navigate))))

;; Indentation: dtrt-indent (via +guess in whitespace module) handles detection.
;; These are fallback defaults if detection fails.
(add-hook 'typst-ts-mode-hook
          (lambda ()
            (setq-local indent-tabs-mode nil)
            (setq-local tab-width 2)
            (setq-local standard-indent 2)
            (setq-local evil-shift-width 2)
            ;; Prevent re-indentation when typing characters like ( or #
            (setq-local electric-indent-inhibit t)
            (setq-local electric-indent-chars nil)))

;; Disable snippet placeholder highlighting (green text / gray background)
(after! yasnippet
  (set-face-attribute 'yas-field-highlight-face nil
                      :background 'unspecified
                      :foreground 'unspecified
                      :inherit nil))

;; Also disable tempel placeholder faces if used
(after! tempel
  (set-face-attribute 'tempel-field nil
                      :background 'unspecified
                      :foreground 'unspecified
                      :inherit nil)
  (set-face-attribute 'tempel-form nil
                      :background 'unspecified
                      :foreground 'unspecified
                      :inherit nil))

(use-package! noteworthy-layout
  :config
  (setq noteworthy-terminal-shell +noteworthy-terminal-cmd))

;; Vterm tweaks specific to this module
(defun +noteworthy-disable-line-numbers-h ()
  (display-line-numbers-mode -1))

(add-hook 'vterm-mode-hook #'+noteworthy-disable-line-numbers-h)

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; Theme: Pitch Black Override
;; We must override solaire-mode faces too because Doom uses them for sidebars/terminals
(custom-set-faces!
  '(default :background "#000000")
  '(fringe :background "#000000")
  '(line-number :background "#000000")
  '(solaire-default-face :background "#000000")
  '(solaire-fringe-face :background "#000000")
  '(treemacs-window-background-face :background "#000000")
  '(term :background "#000000")
  '(vterm :background "#000000"))

;; Treemacs Theme
(after! treemacs
  (treemacs-load-theme "doom-colors"))

;; Eldoc: Show explanation after 0.5s
(setq eldoc-idle-delay 0.5)
(setq eldoc-echo-area-use-multiline-p t)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; Handle command line arguments for Noteworthy
;; Looks for --noteworthy-path and --pdf-path
(let ((path-arg (member "--noteworthy-path" command-line-args))
      (pdf-arg (member "--pdf-path" command-line-args)))
  (when path-arg
    (let ((path (cadr path-arg))
          (pdf-path (and pdf-arg (cadr pdf-arg))))
      (add-hook 'emacs-startup-hook
                (lambda ()
                  (noteworthy-init path pdf-path))))))

(use-package! pdf-view-restore
  :after pdf-tools
  :config
  (add-hook 'pdf-view-mode-hook 'pdf-view-restore-mode)
  (setq pdf-view-restore-filename "~/.emacs.d/.local/cache/pdf-view-restore"))

;; Global Auto-Save Configuration
(auto-save-visited-mode 1)
(setq auto-save-visited-interval 5)

;; Memory Optimization Settings
;; 1. Tune Garbage Collection (GCMH) to be more aggressive (100MB threshold)
(after! gcmh
  (setq gcmh-high-cons-threshold (* 100 1024 1024))
  (setq gcmh-idle-delay 5))

;; Proactive memory pressure monitor
;; Forces cleanup when system RAM exceeds threshold (not relying on idle-GC)
(defvar noteworthy-memory-threshold 95
  "Percentage of system RAM usage that triggers emergency cleanup.")

(defvar noteworthy-memory-check-interval 10
  "Seconds between memory pressure checks.")

(defun noteworthy--get-memory-usage-percent ()
  "Return current system memory usage percentage (excluding swap)."
  (when (file-readable-p "/proc/meminfo")
    (with-temp-buffer
      (insert-file-contents "/proc/meminfo")
      (let ((total 0) (available 0))
        (goto-char (point-min))
        (when (re-search-forward "^MemTotal:\\s-+\\([0-9]+\\)" nil t)
          (setq total (string-to-number (match-string 1))))
        (goto-char (point-min))
        (when (re-search-forward "^MemAvailable:\\s-+\\([0-9]+\\)" nil t)
          (setq available (string-to-number (match-string 1))))
        (when (> total 0)
          (round (* 100.0 (/ (float (- total available)) total))))))))

(defun noteworthy--force-memory-cleanup ()
  "Force garbage collection and return memory to OS."
  (garbage-collect)
  (when (fboundp 'malloc-trim)
    (malloc-trim)))

(defun noteworthy--memory-pressure-check ()
  "Check system memory and force cleanup if over threshold."
  (let ((usage (noteworthy--get-memory-usage-percent)))
    (when (and usage (>= usage noteworthy-memory-threshold))
      (message "⚠️ Memory pressure: %d%% - forcing cleanup..." usage)
      (noteworthy--force-memory-cleanup)
      (let ((new-usage (noteworthy--get-memory-usage-percent)))
        (message "✓ Memory cleanup complete: %d%% → %d%%" usage (or new-usage usage))))))

(defvar noteworthy--memory-timer nil
  "Timer for periodic memory pressure checks.")

(defun noteworthy-start-memory-monitor ()
  "Start the periodic memory pressure monitor."
  (interactive)
  (noteworthy-stop-memory-monitor)
  (setq noteworthy--memory-timer
        (run-with-timer noteworthy-memory-check-interval
                        noteworthy-memory-check-interval
                        #'noteworthy--memory-pressure-check))
  (message "Memory monitor started (checking every %ds, threshold %d%%)"
           noteworthy-memory-check-interval noteworthy-memory-threshold))

(defun noteworthy-stop-memory-monitor ()
  "Stop the periodic memory pressure monitor."
  (interactive)
  (when noteworthy--memory-timer
    (cancel-timer noteworthy--memory-timer)
    (setq noteworthy--memory-timer nil)))

;; Start monitor automatically
(add-hook 'emacs-startup-hook #'noteworthy-start-memory-monitor)

;; 2. Optimize PDF Tools Cache
(after! pdf-tools
  ;; Disable pre-rendering next/prev pages to save RAM
  (setq pdf-cache-prefetch-minor-mode nil)
  ;; Limit image cache size (default is often unlimited or very high)
  (setq pdf-cache-image-limit 32)
  (setq pdf-view-use-scaling t)
  (setq pdf-view-use-imagemagick nil))

;; 3. Limit Undo History (Critical for preventing indefinite memory growth)
(setq undo-limit (* 10 1024 1024))        ; 10MB (default is usually 160kb)
(setq undo-strong-limit (* 50 1024 1024)) ; 50MB (buffer against giant deletions)
(setq undo-outer-limit (* 100 1024 1024)) ; 100MB (absolute hard ceiling)

;; 4. Limit terminal scrollback
(after! vterm
  (setq vterm-max-scrollback 2000))

;; ============================================================
;; Noteworthy Collaboration (Real-time remote editing)
;; ============================================================

(use-package! noteworthy-collab
  :commands (noteworthy-remote-init noteworthy-collab-disconnect noteworthy-collab-status)
  :config
  ;; Port 8001 is the Emacs bridge (noteworthy.bridge.server), NOT Studio on
  ;; 8000 -- Studio speaks binary Yjs, which this client does not.
  (setq noteworthy-collab-server-url "ws://localhost:8001/ws/emacs")

  ;; Your display name for collaboration
  (setq noteworthy-collab-user-name user-login-name)

  ;; Terminal command for remote sessions (same as local)
  (setq noteworthy-collab-terminal-cmd +noteworthy-terminal-cmd)

  ;; Preview: a tinymist session started by hand on the project's machine,
  ;; with both planes forwarded:
  ;;   ssh -L 23625:localhost:23625 -L 23626:localhost:23626 yourserver
  ;; The preview MUST be reached over localhost: tinymist binds 127.0.0.1 and
  ;; refuses any websocket whose Origin is not localhost, and the xwidget sends
  ;; the URL it loaded from as its Origin.  Left unset, the URL is inferred
  ;; from the collab server's host and the pane shows "Connection refused".
  ;; The ports match noteworthy-collab-preview-{data,control}-port.
  (setq noteworthy-collab-preview-url "http://localhost:23627"
        noteworthy-collab-preview-control-url "ws://localhost:23628")
  )

;; Keybindings for collaboration
(map! :leader
      :prefix ("n" . "noteworthy")
      :desc "Remote init" "r" #'noteworthy-remote-init
      :desc "Disconnect" "d" #'noteworthy-collab-disconnect
      :desc "Status" "s" #'noteworthy-collab-status
      :desc "Toggle log" "l" #'noteworthy-collab-toggle-log
      :desc "Connect preview" "p" #'noteworthy-collab-preview-connect)
;;
