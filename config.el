;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(defun my/path-force-first-component (directory)
  "Ensure DIRECTORY appears once and is first on `PATH', and prepend `exec-path'."
  ;; Project shims under `/usr/local/bin' should precede conda/Anaconda shadows.
  (let* ((dir (directory-file-name (expand-file-name directory)))
         (dirs (split-string (or (getenv "PATH") "") path-separator t))
         (without (seq-remove (lambda (d) (string= d dir)) dirs)))
    (setenv "PATH" (mapconcat #'identity (cons dir without) path-separator))
    (setq exec-path (delete dir exec-path))
    (push dir exec-path)))

(defun my/configure-exec-search-path ()
  "`PATH' / `exec-path' tweaks (see `my/path-force-first-component')."
  (my/path-force-first-component "/usr/local/bin")
  (add-to-list 'exec-path "/home/r0k0r/.local/bin" t #'equal))

(my/configure-exec-search-path)
(add-hook 'emacs-startup-hook #'my/configure-exec-search-path)

;; ==========================================
;; 0. TREE-SITTER (shared; not app-specific)
;; ==========================================
;; Doom `:tools tree-sitter' configures built-in `treesit` (features `treesit'), not a `tree-sitter'
;; package: `(after! tree-sitter)' is a no-op — nothing `(provide \'tree-sitter)'. Wrong hook, so use `treesit'.
;;
;; Grammars are Nix-provided (treesit-grammars.with-all-grammars, exposed via
;; $TREESIT_GRAMMAR_DIR -- see modules/home/r0k0r/editors/emacs/doom-config.nix
;; in the flake repo), not fetched/compiled at runtime: `treesit-auto-install-grammar'
;; must stay nil so `*-ts-mode' never shells out to git/gcc on its own.
;; `treesit-auto' still needs `global-treesit-auto-mode' to remap `python-mode' etc.
;; to its `-ts-mode' once a grammar is available.
(after! treesit
  (when-let ((dir (getenv "TREESIT_GRAMMAR_DIR")))
    (add-to-list 'treesit-extra-load-path dir))
  (setq treesit-auto-install-grammar nil)
  (use-package! treesit-auto
    :config
    (setq treesit-auto-install nil)
    (treesit-auto-add-to-auto-mode-alist 'all)
    (global-treesit-auto-mode +1)))

;; ==========================================
;; 1. IDENTITY & VISUALS
;; ==========================================
(setq user-full-name "r0k0r"
      doom-theme 'doom-one)

(setq doom-font (font-spec :family "JetBrainsMonoNL Nerd Font" :size 12.0 :weight 'semi-light)
      doom-variable-pitch-font (font-spec :family "JetBrainsMonoNL Nerd Font" :size 12.0))

(setq display-line-numbers-type t)

;; Pitch Black Override
(custom-set-faces!
  '(default :background "#000000")
  '(fringe :background "#000000")
  '(line-number :background "#000000")
  '(solaire-default-face :background "#000000")
  '(solaire-fringe-face :background "#000000")
  '(treemacs-window-background-face :background "#000000")
  '(term :background "#000000")
  '(vterm :background "#000000")
  ;; Inlay Hints: Light gray/italic to pop against black
  '(lsp-inlay-hint-face :foreground "#666666" :slant italic :weight light))

(custom-set-faces!
  '(flycheck-warning :underline (:style wave :color "#333333"))
  '(flycheck-error   :underline (:style wave :color "#ff0000"))) ; Keep errors red maybe?

(setq display-line-numbers-type t)

;; tinymist color inverting disable
(setq typst-preview-invert-colors "never")

;; Fuck yea glassmorphism
(set-frame-parameter nil 'alpha-background 65)
(diff-hl-margin-mode 1)
(add-to-list 'default-frame-alist '(alpha-background . 65))
(add-hook 'doom-init-ui-hook
          (lambda ()
            (set-frame-parameter nil 'alpha-background 65)))

;; Any custom fringe bitmap (define-fringe-bitmap) -- vi-tilde-fringe's "~"
;; past-EOB indicator, flycheck's error/warning markers, etc. -- composites
;; as solid opaque black instead of blending with the transparent frame.
;; pgtk/Cairo fixed the general fringe *background fill* for
;; alpha-background in Emacs 30, but bitmap glyphs drawn on top of that
;; fill still hit a broken path (unresolved upstream: bug#70697's "insets"
;; half; both affected faces come back fully `unspecified`, not a face
;; misconfig). vi-tilde-fringe is a thin wrapper around Emacs's own
;; built-in indicate-empty-lines + fringe-indicator-alist, so this is a
;; genuine Emacs-core gap, not a third-party bug.
;;
;; Tried and DISPROVEN: (inhibit-double-buffering . t) on the frame. A
;; forced (redraw-frame) after setting it produced one clean screenshot,
;; which looked like a fix, but normal incremental redraws (scrolling,
;; editing) still hit the broken compositing path -- confirmed by
;; reproducing the black boxes again afterwards with the parameter still
;; t. Don't re-try this.
;;
;; Real fix: don't put custom bitmaps in the fringe at all.
;;   - vi-tilde-fringe: no margin-based equivalent readily available, so
;;     just disabled.
;;   - flycheck: has a first-class non-fringe mode -- moved to the right
;;     margin (diff-hl-margin-mode above already owns the left margin, so
;;     right avoids a collision). Text-based margin indicators use the
;;     normal glyph rendering path, which was never broken (margin) --
;;     confirmed by diff-hl-margin-mode already working correctly.
(global-vi-tilde-fringe-mode -1)
(setq-default flycheck-indication-mode 'right-margin)

;; ==========================================
;; 2. SYSTEM & KEYBINDINGS
;; ==========================================
;; Restore Leader Key (SPC) for Emacs 31
(after! evil
  (evil-define-key* '(normal visual) 'global (kbd "SPC") doom-leader-map))

(after! treemacs
  (setq treemacs-persist-file nil)
  ;; Switch to doom-atom if doom-colors continues to warn
  (treemacs-load-theme "doom-colors"))

;; Eldoc speed
(setq eldoc-idle-delay 0.3
      eldoc-echo-area-use-multiline-p t)

;; VTerm shell: use Fish if available, otherwise `shell-file-name`.
(setq vterm-shell (or (executable-find "fish") shell-file-name))

;; Doom hides the mode line in vterm / term / eshell / shell / DAP REPL via
;; `mode-line-invisible-mode', not `hide-mode-line-mode' (see Doom’s
;; modules/term/*/config.el). Remove those hooks and undo both minor modes so the
;; modeline stays visible everywhere we care about.
(defun my/force-show-mode-line ()
  (when (bound-and-true-p hide-mode-line-mode)
    (hide-mode-line-mode -1))
  (when (bound-and-true-p mode-line-invisible-mode)
    (mode-line-invisible-mode -1)))

(after! vterm
  (remove-hook 'vterm-mode-hook #'mode-line-invisible-mode)
  ;; Append so this runs after any remaining `vterm-mode-hook' entries.
  (add-hook 'vterm-mode-hook #'my/force-show-mode-line t))

(after! dape
  (remove-hook 'dape-repl-mode-hook #'mode-line-invisible-mode)
  (add-hook 'dape-repl-mode-hook #'my/force-show-mode-line t))

;; Inferior Python, ielm, `M-x compile`, and other comint-derived REPLs.
(add-hook 'comint-mode-hook #'my/force-show-mode-line t)

(after! shell
  (remove-hook 'shell-mode-hook #'mode-line-invisible-mode)
  (add-hook 'shell-mode-hook #'my/force-show-mode-line t))
(after! term
  (remove-hook 'term-mode-hook #'mode-line-invisible-mode)
  (add-hook 'term-mode-hook #'my/force-show-mode-line t))
(after! eshell
  (remove-hook 'eshell-mode-hook #'mode-line-invisible-mode)
  (add-hook 'eshell-mode-hook #'my/force-show-mode-line t))

;; clipetty
(use-package! clipetty
  :hook (after-init . global-clipetty-mode))

;; xwidgets — Latin keys in edit mode are routed via `xwidget-webkit-pass-command-event'.
;; Evil's maps sit above that minor mode map, so edit mode looked broken (IME/fcitx5 uses a
;; different path and still worked). Use Evil's intercept map while edit mode is on.
(when (featurep 'xwidget-internal)
  (setq browse-url-browser-function #'xwidget-webkit-browse-url)

  (defun my/xwidget-webkit--evil-sync-edit-pass-through ()
    "Give `xwidget-webkit-edit-mode-map' precedence over Evil while edit mode is active.

The edit map substitutes `self-insert-command' bindings into
`xwidget-webkit-pass-command-event' (see Emacs `xwidget.el'); Evil must not mask that."
    (when (featurep 'evil)
      (cond (xwidget-webkit-edit-mode
             (evil-make-intercept-map xwidget-webkit-edit-mode-map nil)
             (evil-normalize-keymaps))
            (t
             ;; Shared keymap: drop intercept only if no buffer still has edit mode on.
             (unless (seq-some (lambda (buf)
                                 (and (buffer-live-p buf)
                                      (buffer-local-value 'xwidget-webkit-edit-mode buf)))
                               (buffer-list))
               (define-key xwidget-webkit-edit-mode-map [intercept-state] nil))
             (evil-normalize-keymaps)))))

  (with-eval-after-load 'xwidget
    (add-hook 'xwidget-webkit-edit-mode-hook #'my/xwidget-webkit--evil-sync-edit-pass-through))

  (defun my/xwidget-webkit-toggle-browser-typing ()
    "Toggle Chrome-like typing: Latin keys go to WebKit via `xwidget-webkit-edit-mode'.

Evil is synced so its keymaps do not block `xwidget-webkit-pass-command-event'.
Toggle again for xwidget navigation keys (`r', `g', …)."
    (interactive)
    (unless (derived-mode-p 'xwidget-webkit-mode)
      (user-error "Not in an xwidget-webkit buffer"))
    (if (bound-and-true-p xwidget-webkit-edit-mode)
        (progn
          (xwidget-webkit-edit-mode -1)
          (when (fboundp 'evil-normal-state)
            (evil-normal-state))
          (message "WebKit typing OFF (xwidget command keys)"))
      (xwidget-webkit-edit-mode +1)
      (when (fboundp 'evil-insert-state)
        (evil-insert-state))
      (message "WebKit typing ON (Latin keys to page)")))

  (map! :map xwidget-webkit-mode-map
        :n "C-c C-k" #'my/xwidget-webkit-toggle-browser-typing
        :i "C-c C-k" #'my/xwidget-webkit-toggle-browser-typing
        :v "C-c C-k" #'my/xwidget-webkit-toggle-browser-typing))

;; markdown-mode's preview wraps compiled output in XHTML 1.0 Strict with an
;; `<?xml?>' declaration (`markdown-add-xhtml-header-and-footer'), which makes
;; xwidget-webkit parse the page as strict XML. Doom's default
;; `markdown-xhtml-header-content' is HTML5 (bare `async', unclosed <meta>), and
;; so is raw HTML common in READMEs (unclosed <img>) -- each is a fatal XML
;; parse error, so WebKit shows "This page contains the following errors" and
;; renders nothing past the first one. Fixing individual tags is whack-a-mole;
;; emit an HTML5 header instead so the forgiving HTML parser is used.
(after! markdown-mode
  (defun my/markdown-add-html5-header-and-footer (title)
    "Wrap an HTML5 header and footer with TITLE around current buffer."
    (goto-char (point-min))
    (insert "<!DOCTYPE html>\n"
            "<html>\n<head>\n"
            "<meta charset=\"utf-8\">\n"
            "<title>" (markdown-escape-title title) "</title>\n")
    (when (> (length markdown-css-paths) 0)
      (insert (mapconcat #'markdown-stylesheet-link-string markdown-css-paths "\n")))
    (when (> (length markdown-xhtml-header-content) 0)
      (insert markdown-xhtml-header-content))
    (insert "\n</head>\n<body>\n")
    (when (> (length markdown-xhtml-body-preamble) 0)
      (insert markdown-xhtml-body-preamble "\n"))
    (goto-char (point-max))
    (when (> (length markdown-xhtml-body-epilogue) 0)
      (insert "\n" markdown-xhtml-body-epilogue))
    (insert "\n</body>\n</html>\n"))

  (advice-add 'markdown-add-xhtml-header-and-footer
              :override #'my/markdown-add-html5-header-and-footer))

;; ==========================================
;; 3. PYTHON & REPL (Fixes VS Code Corruption)
;; ==========================================
(after! python
  (setenv "TERM_PROGRAM" "dumb")
  (setenv "TERM" "dumb")
  (setenv "VSCODE_IPC_HOOK_CLI" nil)
  (setenv "VSCODE_SHELL_INTEGRATION" nil)
  (setq python-shell-interpreter "python3"
        python-shell-interpreter-args "-i")
  (setenv "QT_QPA_PLATFORM" "xcb")
  (setenv "QT_AUTO_SCREEN_SCALE_FACTOR" "1")
  ;; Still disable this—it's the #1 cause of TRAMP hangs
  (setq python-shell-completion-native-enable nil)
  (advice-add '+python-executable-find :around #'my/+python-executable-find-with-fallback))

;; ==========================================
;; 4. LSP & INTELLIGENCE (BasedPyright + Ruff)
;; ==========================================

(after! lsp-mode
  ;; :none, not :capf/t -- Doom runs corfu, which consumes
  ;; `completion-at-point-functions' natively, so lsp must not try to configure
  ;; a backend itself. Left at t (its "auto-configure company-mode" value) it
  ;; warns "Unable to autoconfigure company-mode" on every buffer, since company
  ;; isn't installed at all here.
  (setq lsp-completion-provider :none)

  ;; 1. THE FIX: Allow all valid clients, and STOP disabling pyright
  (setq lsp-enabled-clients nil)
  (setq lsp-disabled-clients '(pylsp pyls ruff-lsp semgrep-ls ty-ls mspyls))

  (setq lsp-modeline-code-actions-enable t
        lsp-inlay-hint-enable t)

  (add-to-list 'lsp-language-id-configuration '(python-ts-mode . "python")))

;; No hand-rolled `lsp-deferred' hook here: Doom's (python +lsp) flag already
;; puts `lsp!' on BOTH `python-mode-local-vars-hook' and
;; `python-ts-mode-local-vars-hook', so tree-sitter Python is covered. Adding a
;; second starter on the main mode hook started the server twice per buffer --
;; visible as duplicated "Connected to [pyright-remote:...]" and
;; "Received redundant open text document command for ...".

;; Prefer LSP + yasnippet CAPF first, but keep Doom's cape-dabbrev / cape-file hooks.
;; Raw `lsp-completion-at-point' errors if invoked before a server is ready or when
;; the workspace has no `textDocument/completion' (Corfu idle timer); guard it.
(defun my-lsp-completion-capf ()
  (when (and (bound-and-true-p lsp-mode)
             (fboundp 'lsp-feature?)
             (lsp-feature? "textDocument/completion"))
    (lsp-completion-at-point)))

;; Do not set `completion-in-region-function' to `corfu--in-region' here: Corfu already
;; wires that via `global-corfu-mode'; a local override can fall through to
;; `completion--in-region' (buffer insertion) when popups are unavailable, or interact
;; badly with Corfu's internal dispatch (see `corfu--in-region' in corfu.el).
(defun force-corfu-pipes-h ()
  (corfu-mode 1)
  (setq-local completion-at-point-functions
              (append (list #'my-lsp-completion-capf #'yasnippet-capf)
                      (delq #'yasnippet-capf
                            (delq #'my-lsp-completion-capf
                                  (delq #'lsp-completion-at-point completion-at-point-functions))))))

(add-hook 'python-ts-mode-hook #'force-corfu-pipes-h 'append)
(add-hook 'python-mode-hook #'force-corfu-pipes-h 'append)
(add-hook 'lsp-completion-mode-hook #'force-corfu-pipes-h)

(after! lsp-mode
  ;; Force LSP to only care about the project the current file is in.
  (setq lsp-session-file (expand-file-name ".lsp-session" doom-cache-dir))
  (setq lsp-keep-workspace-alive nil) ;; Close the LSP server when the last buffer closes
  (setq lsp-auto-configure t))

(after! corfu
  ;; After these chars, idle Corfu ignores `corfu-auto-prefix` (e.g. member access after `.` in Dart/Flutter).
  (setq corfu-auto-trigger ".(["))

;; ==========================================
;; 5. DEBUGGER (DAPE)
;; ==========================================
(after! dape
  (setq dape-env `(("TERM" . "dumb") ("TERM_PROGRAM" . "dumb")))

  ;; Wipe old attempts
  (setq dape-configs (assoc-delete-all 'python-run-file dape-configs))

  (add-to-list 'dape-configs
               `(python-run-file
                 command "python3"
                 args ("-m" "debugpy" "--listen" "0.0.0.0:5678" "--wait-for-client" ,(lambda () (buffer-file-name)))
                 port 5678
                 host "127.0.0.1"
                 :request "launch"
                 :type "python"
                 :cwd ,(lambda () (file-name-directory (buffer-file-name))))))

;; ==========================================
;; 6. NOTEWORTHY COURSES
;; ==========================================

(defun calculus1-noteworthy-init ()
  "Initialize Calculus I KSA Course"
  (interactive)
  (let ((project-dir (expand-file-name "~/Typst/KSA/calculus-1/"))
        (pdf-path (expand-file-name "~/Downloads/Calculus9eStewart_ISBN 978-1-337-62418-3 Red cover.pdf")))
    (noteworthy-init project-dir pdf-path)))

(defun calculus1-noteworthy-no-pdf ()
  "Initialize Calculus I KSA Course without a PDF"
  (interactive)
  (let ((project-dir (expand-file-name "~/Typst/KSA/calculus-1/")))
    (noteworthy-init project-dir nil)))

;; ==========================================
;; 7. KITTY TUI IMAGES
;; ==========================================

(setq kitty-graphics-enable-video t)
(kitty-graphics-setup)

;; Tinymist preview inside `emacs -nw'.  A terminal frame cannot show an
;; xwidget, and the "default" browser means a separate Chrome window, so on a
;; terminal the preview goes to kitty-graphics' inline browser instead: casty
;; drives headless Chrome and paints the page into the buffer with the Kitty
;; graphics protocol.  GUI frames are untouched -- they keep the xwidget.
;;
;; casty comes from the Nix emacs feature (features/emacs/casty.nix).  It is
;; pointed at the Chrome already installed so it never downloads its own.
(setq kitty-graphics-enable-browser t)

(defun my/kitty-preview-p ()
  "Non-nil when this frame should show previews in kitty-graphics' browser."
  (and (not (display-graphic-p))
       (fboundp 'kitty-graphics--browser-available-p)
       (kitty-graphics--browser-available-p)))

(defvar my/kitty-preview--retry-timer nil
  "Pending check that reloads the kitty browser once its server answers.")

(defun my/kitty-preview-show (url)
  "Open URL in kitty-graphics' inline browser, in the preview side window.
Reuses the window Noteworthy marks as its preview, so a Noteworthy layout
and a plain `typst-preview-mode' session put it in the same place."
  (unless kitty-graphics-casty-chrome
    (setq kitty-graphics-casty-chrome
          (or (executable-find "google-chrome-stable")
              "/run/current-system/sw/bin/google-chrome-stable")))
  (let* ((existing (window-with-parameter 'noteworthy-preview t))
         (win (or existing (split-window (frame-root-window) nil 'right))))
    (set-window-parameter win 'noteworthy-preview t)
    ;; Same width the xwidget preview gets.  A window the layout already made
    ;; is sized by it exactly as for the xwidget, so leave it be; a new one is
    ;; sized by the layouts' own rule -- their width setting, else 35% of the
    ;; frame.  Before casty starts, which reads the size from the window.
    (unless existing
      (let ((target (or (bound-and-true-p noteworthy-collab-preview-width)
                        (bound-and-true-p noteworthy-preview-width)
                        (round (* 0.35 (frame-width))))))
        (ignore-errors (window-resize win (- target (window-total-width win)) t))))
    (set-window-dedicated-p win nil)
    (my/kitty-preview--ensure-local url)
    ;; Whether the page is about to load before its server answers -- only
    ;; then does it need loading again.
    (let* ((port (my/kitty-preview--local-port url))
           (early (and port (not (my/kitty-preview--port-up-p port)))))
      (with-selected-window win
        (kitty-graphics-browse url))
      (set-window-dedicated-p win t)
      (if early
          (my/kitty-preview--reload-when-up url)
        (when (timerp my/kitty-preview--retry-timer)
          (cancel-timer my/kitty-preview--retry-timer))))))

(defun my/kitty-preview--local-port (url)
  "The port of URL when it points at this machine, else nil."
  (when (string-match "\\`https?://\\(localhost\\|127\\.0\\.0\\.1\\|\\[::1\\]\\):\\([0-9]+\\)" url)
    (string-to-number (match-string 2 url))))

(defun my/kitty-preview--port-up-p (port)
  "Non-nil when something accepts connections on localhost PORT."
  (condition-case nil
      (progn (delete-process (open-network-stream "kitty-preview-probe" nil "127.0.0.1" port)) t)
    (error nil)))

(defun my/kitty-preview--ensure-local (url)
  "Bring up whatever serves URL locally before the browser asks for it.
A collab preview lives on the project host and is reached through an SSH
tunnel that `noteworthy-collab-preview-start' opens -- but the layout
shows the pane as soon as it knows the URL, which can be first.  The
xwidget got away with that by being reloaded later; casty loads once."
  (when (and (my/kitty-preview--local-port url)
             (not (my/kitty-preview--port-up-p (my/kitty-preview--local-port url)))
             (fboundp 'noteworthy-collab-preview-ensure-tunnel))
    (ignore-errors (noteworthy-collab-preview-ensure-tunnel))))

(defun my/kitty-preview--reload-when-up (url &optional tries)
  "Reload the kitty browser once URL's local port answers.
Called only when the page loaded before its server did.  Checks every
second for up to 30 seconds, then gives up."
  (when (timerp my/kitty-preview--retry-timer)
    (cancel-timer my/kitty-preview--retry-timer))
  (let ((port (my/kitty-preview--local-port url))
        (tries (or tries 0)))
    (when (and port (< tries 30))
      (setq my/kitty-preview--retry-timer
            (run-at-time
             1 nil
             (lambda ()
               (setq my/kitty-preview--retry-timer nil)
               (if (my/kitty-preview--port-up-p port)
                   (when (get-buffer "*kitty-browser*")
                     (with-current-buffer "*kitty-browser*"
                       (ignore-errors (kitty-graphics-browser-reload))))
                 (my/kitty-preview--reload-when-up url (1+ tries)))))))))

(defun my/kitty-preview--xwidget-browse (orig url &rest args)
  "On a terminal frame, show URL in kitty-graphics instead of an xwidget.
ORIG and ARGS are `xwidget-webkit-browse-url' and its arguments."
  (if (my/kitty-preview-p)
      (my/kitty-preview-show url)
    (apply orig url args)))

(defun my/kitty-preview--typst-connect (orig browser hostname)
  "On a terminal frame, open the typst preview at HOSTNAME in kitty-graphics.
ORIG is `typst-preview--connect-browser', given BROWSER and HOSTNAME."
  (if (my/kitty-preview-p)
      (my/kitty-preview-show (concat "http://" hostname))
    (funcall orig browser hostname)))

;; Outermost, so it decides before Noteworthy's side-window advice creates a
;; window the xwidget would otherwise have gone into.
(advice-add 'xwidget-webkit-browse-url :around #'my/kitty-preview--xwidget-browse
            '((depth . -100)))
(advice-add 'typst-preview--connect-browser :around #'my/kitty-preview--typst-connect)

;; The browser frame follows its window's size.  kitty-graphics sizes casty
;; once, at launch, and afterwards only ever tells it where the frame moved
;; (`set-geometry' with :top/:left), so after a resize the page kept its
;; original width and ran past the window.  casty's `set-geometry' also takes
;; :cols/:rows and re-emulates the viewport; this sends them whenever the
;; window's usable size changes, sized exactly as `kitty-graphics-browse' does.
(defun my/kitty-browser--follow-size ()
  "Resize this buffer's casty frame to its window.  Runs in the browser buffer."
  (when (and kitty-graphics--browser-process
             (process-live-p kitty-graphics--browser-process)
             kitty-graphics--browser-overlay
             (not (active-minibuffer-window)))
    (when-let* ((win (kitty-graphics--browser-canonical-window)))
      (let ((cols (max 1 (min (1- (window-body-width win)) kitty-graphics-browser-max-width)))
            (rows (max 1 (min (1- (window-body-height win)) kitty-graphics-browser-max-height))))
        (unless (and (eql cols kitty-graphics--browser-cols)
                     (eql rows kitty-graphics--browser-rows))
          ;; The buffer holds one blank line per frame row -- that is what
          ;; reserves the space.  The overlay is rear-advancing, so lines
          ;; added at the end join it and lines removed shrink it.
          (let ((inhibit-read-only t)
                (have (count-lines (point-min) (point-max))))
            (save-excursion
              (cond
               ((< have rows)
                (goto-char (point-max))
                (insert (make-string (- rows have) ?\n)))
               ((> have rows)
                (goto-char (point-min))
                (forward-line rows)
                (delete-region (point) (point-max))))))
          (setq kitty-graphics--browser-cols cols
                kitty-graphics--browser-rows rows)
          (let ((pos (kitty-graphics--browser-overlay-position win)))
            (kitty-graphics--browser-send
             (append (list :cmd "set-geometry" :cols cols :rows rows)
                     (when pos (list :top (car pos) :left (cdr pos)))))))))))

(advice-add 'kitty-graphics--refresh-browser-overlay :after #'my/kitty-browser--follow-size)

;; The cursor, and what you type, must stay where Emacs put them.  casty
;; positions every frame by moving the terminal cursor to the frame's corner
;; (`ESC [ row ; col H') and never puts it back, and kitty-graphics forwards
;; that straight to the terminal.  Emacs does not know the cursor moved, so
;; its next update -- the character just typed -- landed relative to the
;; preview's top-left until a full redraw (a scroll) repainted everything.
;; Each forwarded run is now wrapped in save-cursor / restore-cursor (DECSC
;; `ESC 7', DECRC `ESC 8').  Output reaches the filter in arbitrary pieces,
;; and a restore inside a half-sent escape would corrupt it, so only complete
;; frames go out -- up to the last string terminator `ESC \' -- and the rest
;; waits for the next piece.
(defun my/kitty-browser--keep-cursor (orig proc chunk)
  "Forward casty CHUNK with the cursor saved and restored around it.
ORIG is `kitty-graphics--mpv-filter'; PROC is the process."
  (if (not (string-prefix-p "kitty-graphics-casty" (process-name proc)))
      (funcall orig proc chunk)
    (let* ((pending (concat (or (process-get proc 'my-kitty-pending) "") chunk))
           (end (let ((i (string-search "\e\\" pending)) last)
                  (while i (setq last (+ i 2) i (string-search "\e\\" pending last)))
                  (cond
                   ;; A new escape has begun after the last frame: hold it.
                   ((string-search "\e" pending (or last 0)) (or last 0))
                   ;; Nothing left that is escape-like: send it all.
                   (t (length pending))))))
      (process-put proc 'my-kitty-pending (substring pending end))
      (when (> end 0)
        ;; Terminal modes are Emacs's.  casty leaves them alone in embed mode
        ;; except on its error path, which switches mouse reporting off and
        ;; the cursor on -- for the whole terminal, behind Emacs's back.
        (funcall orig proc (concat "\e7"
                                   (replace-regexp-in-string
                                    "\e\\[\\?[0-9;]*[hl]" "" (substring pending 0 end) t t)
                                   "\e8"))))))

(advice-add 'kitty-graphics--mpv-filter :around #'my/kitty-browser--keep-cursor)

;; The mouse, in every terminal frame.  Emacs 31 turns `xterm-mouse-mode' on by
;; itself only after identifying the terminal from its XTVERSION reply, and
;; waits for that reply only briefly.  Under kitty-graphics' own start-up
;; probing the reply comes late -- "No catch for tag: result, kitty(0.48.2)"
;; at start-up -- so the mouse was never enabled: clicks became Kitty's text
;; selection, and the preview browser got no clicks or wheel at all.  Doom's
;; :os tty does exactly this before Emacs 31 and leaves it to the detection
;; from 31 on.
(add-hook 'tty-setup-hook #'xterm-mouse-mode)

;; PDFs inside `emacs -nw'.  Doom's :tools pdf opens every PDF in pdf-tools'
;; `pdf-view-mode', which draws pages as Emacs images a terminal cannot show,
;; and kitty-graphics does not hook pdf-view at all: its PDF support is
;; `doc-view-mode', which it teaches to render in the terminal (pages are
;; converted to PNG with Ghostscript or mutool).  So on a terminal frame with
;; kitty-graphics active, a PDF opens in doc-view instead.  GUI frames keep
;; pdf-tools.
;; doc-view's own variable, bound around `doc-view-mode' below.  Declared so
;; that binding is dynamic -- this file is lexically bound, and doc-view is
;; not loaded yet the first time a PDF opens, so without it the `let' made a
;; private lexical variable doc-view never saw, and reading it signalled
;; void-variable ("File mode specification error").
(defvar doc-view-resolution)

(defun my/kitty-pdf--use-doc-view (orig &rest args)
  "Open the PDF in `doc-view-mode' on a kitty-graphics terminal frame.
ORIG and ARGS are `pdf-view-mode' and its arguments."
  (cond
   ((or (display-graphic-p) (not (bound-and-true-p kitty-graphics-mode)))
    (apply orig args))
   ;; Already showing in doc-view: leave it.  `pdf-tools-install' ends by
   ;; switching every PDF buffer not in pdf-view to pdf-view -- which lands
   ;; here -- and the Noteworthy layout calls it just before opening its PDF.
   ;; Running doc-view again killed the conversion it had just started, so
   ;; the page showed for a moment and was gone.
   ((derived-mode-p 'doc-view-mode) nil)
   (t
    ;; Render at the resolution kitty-graphics will want from the start.
    ;; Otherwise the first page comes out at doc-view's 100 dpi, is shown --
    ;; the cover -- and kitty-graphics, finding it too coarse for the
    ;; window, raises the resolution and reconverts the whole document,
    ;; which deletes every page image: the cover vanished, and a 1300-page
    ;; book started over.  Bound around the mode so the conversion it
    ;; starts uses it, and kept buffer-local for later reconversions.
    (require 'doc-view)
    (let ((dpi (my/kitty-pdf--dpi)))
      (let ((doc-view-resolution dpi))
        (doc-view-mode))
      (setq-local doc-view-resolution dpi))
    (my/kitty-pdf--drop-text)
    (add-hook 'after-revert-hook #'my/kitty-pdf--drop-text nil t)
    (add-hook 'write-contents-functions #'my/kitty-pdf--refuse-save nil t))))

(defun my/kitty-pdf--dpi ()
  "The DPI at which a page passes kitty-graphics' sharpness check first time.
kitty-graphics wants `kitty-graphics-doc-view-resolution-scale' times the
pixels the page is drawn into, and reconverts above 10% short.  The page
size is not known before conversion, so this assumes a Letter page and
takes the larger of the width and height demands -- enough for Letter,
A4 and most books whichever way they fit -- plus that 10%.  A smaller
page than that still gets one reconversion from kitty-graphics' own check."
  (when (fboundp 'kitty-graphics--query-cell-size)
    (ignore-errors (kitty-graphics--query-cell-size)))
  (let* ((win (selected-window))
         (cw (or (bound-and-true-p kitty-graphics--cell-pixel-width)
                 (terminal-parameter nil 'kitty-graphics-cell-w) 8))
         (ch (or (bound-and-true-p kitty-graphics--cell-pixel-height)
                 (terminal-parameter nil 'kitty-graphics-cell-h) 16))
         (w-px (* cw (max 1 (1- (window-body-width win)))))
         (h-px (* ch (max 1 (1- (window-body-height win)))))
         (scale (or (bound-and-true-p kitty-graphics-doc-view-resolution-scale) 1.0)))
    (max doc-view-resolution
         (ceiling (* 1.1 scale (max (/ w-px 8.5) (/ h-px 11.0)))))))

;; No version control in a PDF viewer.  Visiting a file runs `vc-refresh-state'
;; -- and Doom's diff gutter -- from `find-file-hook', synchronously, and in a
;; big repository that is `git status' on the PDF: 12.7 s for the 76 MB
;; Stewart in ~/KSA (a 9.8 GB repository) before git had refreshed its record
;; of it.  Emacs froze in there and C-g led to the emergency escape; the diff
;; gutter had also been marking every line of a raw 90 MB PDF.  A buffer-local
;; `vc-handled-backends' of nil, set from the mode hook -- which runs before
;; `find-file-hook' -- means neither ever asks git.
(defun my/pdf-no-vc ()
  "Keep version control away from this PDF buffer."
  (setq-local vc-handled-backends nil))

(add-hook 'doc-view-mode-hook #'my/pdf-no-vc)
(add-hook 'pdf-view-mode-hook #'my/pdf-no-vc)

(defun my/kitty-pdf--drop-text ()
  "Replace this doc-view buffer's text -- the raw PDF -- with one character.
doc-view renders pages from the file and keys its cache on the file's
contents, so for a local PDF the text is dead weight once the mode is up.  Left in, every walk the
display engine makes over the page overlay crosses the whole file: 90 MB
for a textbook, which is what hung Emacs.  A revert reinserts it, hence
`after-revert-hook'."
  (when (and (derived-mode-p 'doc-view-mode)
             (bound-and-true-p doc-view--buffer-file-name)
             ;; Local PDFs only.  For a remote one doc-view renders from a
             ;; copy it writes FROM THE BUFFER -- at mode setup, on revert,
             ;; when toggling back from the text view -- so a placeholder
             ;; there would become the copy.
             (equal doc-view--buffer-file-name buffer-file-name)
             (file-readable-p doc-view--buffer-file-name)
             (> (buffer-size) 1))
    (let ((inhibit-read-only t)
          (buffer-undo-list t))
      (erase-buffer)
      (insert " ")
      ;; Page overlays made before this -- a cached document is drawn during
      ;; the mode's own setup -- collapsed to nothing with the text, and the
      ;; placeholder went in front of them.  An empty overlay shows nothing,
      ;; so the page vanished and doc-view's welcome text stayed.  Stretch
      ;; them back over the buffer.
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (or (overlay-get ov 'doc-view) (overlay-get ov 'kitty-graphics))
          (move-overlay ov (point-min) (point-max))))
      (goto-char (point-min))
      (set-buffer-modified-p nil))))

(defun my/kitty-pdf--refuse-save ()
  "Never write this buffer: its text is a placeholder, not the PDF.
Returns non-nil so saving stops here without touching the file."
  (message "This PDF is shown from its file; the buffer is not saved")
  t)

;; Outermost, so Doom's epdfinfo advice on the same function never runs for a
;; terminal frame (it would try to start the pdf-tools server for nothing).
(advice-add 'pdf-view-mode :around #'my/kitty-pdf--use-doc-view '((depth . -100)))

;; doc-view converts with mutool when it is on PATH (the Nix emacs feature
;; puts it there).  The Ghostscript converter first checks for a password by
;; running Ghostscript over the WHOLE document, synchronously -- 46 s of
;; frozen Emacs on a 1300-page textbook, which is where C-g led to the
;; emergency escape.  mutool's check draws page 1 only.  PNG rather than SVG
;; pages: kitty-graphics transmits PNG as is, while SVG goes through
;; ImageMagick first.
(setq doc-view-mupdf-use-svg nil)

;; Big PDFs hung Emacs.  kitty-graphics re-places the doc-view page on every
;; refresh, and to find where it goes it asks the display engine --
;; `window-end' with UPDATE, `pos-visible-in-window-p', `posn-at-point' --
;; about the page overlay, which covers the entire buffer: in doc-view that
;; is the whole PDF file as text, 90 MB for a textbook.  A 90 MB Stewart
;; stalled there (in `Fprevious_single_char_property_change', under a
;; refresh timer) until the emergency escape.
;;
;; None of that is needed for a doc-view page.  The overlay starts at the
;; buffer's first character and doc-view keeps it at the window's start, so
;; it sits at the top-left of the window's text area, always.  Answer that
;; directly for doc-view overlays and leave every other image to the original.
(defun my/kitty-doc-view--screen-pos (orig ov &optional win)
  "Screen position of OV, computed directly when it is a doc-view page.
ORIG is `kitty-graphics--overlay-screen-pos'; WIN as there."
  (if (not (overlay-get ov 'kitty-graphics-doc-view))
      (funcall orig ov win)
    (let* ((buf (overlay-buffer ov))
           (pos (overlay-start ov))
           (win (and buf
                     (or (and (window-live-p win) (eq (window-buffer win) buf) win)
                         (get-buffer-window buf)))))
      ;; Same answer as the original: nil when the page is not what the
      ;; window shows from its top, else (TERM-ROW . TERM-COL), 1-based.
      (when (and win pos (= (window-start win) pos))
        (let ((body (window-body-edges win)))
          (cons (+ (nth 1 body) 1)
                ;; The page starts in column 0, so horizontal scroll never
                ;; moves it: the original's visual column is always 0 here.
                (+ (nth 0 body)
                   (kitty-graphics--window-line-number-width win)
                   1)))))))

(advice-add 'kitty-graphics--overlay-screen-pos :around #'my/kitty-doc-view--screen-pos)

;; ==========================================
;; 7. FOOT TUI IMAGES
;; ==========================================

;; Ensure /usr/local/bin is at the absolute front of the path
(setenv "PATH" (concat "/usr/local/bin:" (getenv "PATH")))
(add-to-list 'exec-path "/usr/local/bin")

;; Force AUCTeX to re-check the path
(setq TeX-check-path '("/usr/local/bin"))


;; ==========================================
;; 8. GNUS CONFIGURE
;; ==========================================

;; 1. Global Identity Setup
(setq user-full-name "R0K0R Lee"
      user-mail-address "injoystickly@gmail.com")

(after! gnus
  ;; 2. Server & Method Settings
  (setq gnus-fetch-old-headers t)
  (setq gnus-keep-backlog 50)
  (setq gnus-select-method '(nntp "news.gmane.io"))
  ;; `nnimap-user' is REQUIRED here, not optional: both servers share
  ;; `nnimap-address' "imap.gmail.com" (ksa is Google Workspace), and
  ;; `nnimap-credentials' looks credentials up with
  ;; (auth-source-search :host address :port ports :user user).
  ;; With user nil for both, auth-source returns the SAME first matching
  ;; line twice and both servers silently log into one account -- "ksa"
  ;; showing gmail's mail. The SMTP side already disambiguates by From
  ;; header (`my-gnus-set-smtp-user-safe' below); this is the IMAP
  ;; equivalent, and it means ~/.authinfo.gpg needs one line per account
  ;; for the same machine, distinguished by `login'.
  (setq gnus-secondary-select-methods
        '((nnimap "gmail"
                  (nnimap-address "imap.gmail.com")
                  (nnimap-user "injoystickly@gmail.com")
                  (nnimap-server-port "imaps")
                  (nnimap-stream ssl))
          (nnimap "ksa"
                  (nnimap-address "imap.gmail.com")
                  (nnimap-user "25-095@ksa.hs.kr")
                  (nnimap-server-port "imaps")
                  (nnimap-stream ssl))
          (nntp "eternal-september"
                (nntp-address "news.eternal-september.org"))
          ;; lore.kernel.org: public-inbox over NNTP, read-only and
          ;; UNAUTHENTICATED -- it needs no ~/.authinfo line, unlike the two
          ;; servers above. The greeting is "201 ... ready - post via email",
          ;; i.e. every group is posting-disallowed (`n' in LIST ACTIVE) by
          ;; design: you reply to kernel lists by mailing them, not by posting
          ;; to the newsgroup. Plain 119 only; 563/NNTPS is not served.
          ;;
          ;; Group names mirror the list's DOMAIN, not the kernel.org tree, so
          ;; they are not guessable from the list address alone:
          ;;   org.kernel.vger.linux-kernel   LKML          (6.4M articles)
          ;;   org.kvack.linux-mm             linux-mm      (590k) -- kvack.org,
          ;;                                  NOT vger, hence org.kvack.*
          ;;   org.kernel.vger.mm-commits     mm-commits    (177k)
          ;; Browse the rest with `A A' in the Group buffer, or `LIST ACTIVE
          ;; *pattern*' against nntp.lore.kernel.org directly.
          (nntp "lore"
                (nntp-address "nntp.lore.kernel.org")
                (nntp-port-number 119))))
  ;; 2b. lore groups -> mailing-list address, COMPUTED, not enumerated.
  ;;
  ;; lore refuses posting: its greeting is "201 ... post via email" and every
  ;; group is `n' in LIST ACTIVE, because it is an archive mirror rather than a
  ;; gateway. gmane answers "200 ... (posting ok)" and marks its list groups `m'
  ;; (moderated), so an NNTP post there IS forwarded to the list. That is a
  ;; server property; no client setting changes it. Hence: read on lore, send
  ;; over SMTP.
  ;;
  ;; A lore group name is the list address with the DOMAIN REVERSED and the
  ;; local part last, so the address is derivable and never needs listing:
  ;;   org.kvack.linux-mm            -> linux-mm@kvack.org
  ;;   org.kernel.vger.linux-kernel  -> linux-kernel@vger.kernel.org
  ;;   dev.linux.lists.iommu         -> iommu@lists.linux.dev
  ;; Verified against a full LIST ACTIVE: 356 groups, 41 distinct domains, zero
  ;; that fail to convert. Enumerating them would have covered 74% with three
  ;; rules and gone stale the moment a list was added.
  ;;
  ;; WHY NOT `gnus-parameters': its values expand through `replace-match'
  ;; (`gnus-expand-group-parameter'), so \\1 can SUBSTITUTE but cannot REORDER,
  ;; and reversing the domain is exactly a reorder. Parameter values are also
  ;; returned verbatim -- there is no `eval' hook for them -- so the computation
  ;; has to happen at message-setup time instead.
  (defun my/lore-list-address (group)
    "Mailing-list address for a lore.kernel.org GROUP, or nil if not one."
    (when (and (stringp group)
               (string-match "\\`nntp\\+lore:\\(.+\\)\\'" group))
      (let* ((parts (split-string (match-string 1 group) "\\." t))
             (local (car (last parts)))
             (domain (mapconcat #'identity (reverse (butlast parts)) ".")))
        (when (and local (not (string-empty-p domain)))
          (concat local "@" domain)))))

  ;; 3. Dynamic Posting Styles (Safe against nil/Corfu crashes)
  (setq gnus-posting-styles
        '((".*" ;; Default identity
           (address "injoystickly@gmail.com")
           (name "R0K0R Lee"))
          ((lambda ()
             ;; Check if variable exists and is a string before matching
             (and (boundp 'gnus-newsgroup-name)
                  (stringp gnus-newsgroup-name)
                  (string-match-p "ksa" gnus-newsgroup-name)))
           (address "25-095@ksa.hs.kr")
           (name "이호준"))))

  (setq gnus-case-fold-groups t))

(custom-set-faces!
  '(gnus-group-news-low-empty :inherit default)
  '(gnus-group-news-low :inherit default))

(after! message
  ;; 4. SMTP Global Configuration
  (setq smtpmail-smtp-server "smtp.gmail.com"
        smtpmail-smtp-service 465
        smtpmail-stream-type 'ssl)

  ;; 5. Header Fixer (Prevents Corfu crashes in non-Gnus buffers)
  (defun my-doom-gnus-header-fix-safe ()
    "Forces correct From header based on group name with nil-safety."
    (when (derived-mode-p 'message-mode)
      (let ((group (if (and (boundp 'gnus-newsgroup-name) (stringp gnus-newsgroup-name))
                       gnus-newsgroup-name
                     ""))) ;; Fallback to empty string to avoid string-match error
        (cond
         ((string-match-p "ksa" group)
          (save-excursion (message-replace-header "From" "이호준 <25-095@ksa.hs.kr>")))
         ;; Kernel identity. MUST match `git config user.email' exactly: this
         ;; address becomes the From: on list mail, and git puts the same one in
         ;; Signed-off-by:. A mismatch makes a patch and its own follow-up
         ;; discussion look like two different people, which maintainers notice.
         ;;
         ;; Matches both archives of the same lists -- lore (read-only, replied
         ;; to by mail) and gmane (which does gateway NNTP posts to the list) --
         ;; so the identity does not depend on which one the article was read
         ;; from.
         ((string-match-p "\\(^nntp\\+lore:\\|gmane\\.linux\\.kernel\\)" group)
          (save-excursion (message-replace-header "From" "Joy H.J. Lee <rkr0k0r@gmail.com>")))
         (t
          (save-excursion (message-replace-header "From" "R0K0R Lee <injoystickly@gmail.com>")))))))

  (add-hook 'message-setup-hook #'my-doom-gnus-header-fix-safe)

  ;; Fill To: with the list address when composing from a lore group.
  ;;
  ;; Only when To: is EMPTY, so it never touches a reply -- `S W' (wide reply)
  ;; already gets the right recipients from the article's own headers, which
  ;; lore preserves intact. This is for starting a new thread with `m'.
  ;;
  ;; Use `m' rather than `a' in lore groups: `a' composes a news article and
  ;; would be refused by the server. On gmane, where posting IS allowed, `a'
  ;; remains the right key and this hook stays out of the way.
  (defun my/gnus-fill-lore-recipient ()
    "Set To: to the mailing list when composing in a lore group."
    (when (derived-mode-p 'message-mode)
      (let ((addr (my/lore-list-address
                   (and (boundp 'gnus-newsgroup-name) gnus-newsgroup-name))))
        (when addr
          (save-excursion
            (save-restriction
              (message-narrow-to-headers)
              (let ((to (message-fetch-field "To")))
                (when (or (null to) (string-empty-p (string-trim to)))
                  (message-replace-header "To" addr)))))))))

  (add-hook 'message-setup-hook #'my/gnus-fill-lore-recipient)

  ;; 6. Dynamic SMTP Login Selection
  (defun my-gnus-set-smtp-user-safe ()
    "Sets SMTP username by looking at the From header before sending."
    (save-excursion
      (save-restriction
        (message-narrow-to-headers)
        (let ((from (message-fetch-field "from")))
          (cond
           ((and (stringp from) (string-match-p "25-095@ksa\\.hs\\.kr" from))
            (setq smtpmail-smtp-user "25-095@ksa.hs.kr"))
           ;; Keyed off From: rather than off the group, so it stays correct for
           ;; a message composed outside Gnus entirely. Requires its own line in
           ;; the authinfo secret:
           ;;   machine smtp.gmail.com login rkr0k0r@gmail.com port 465 password <app-password>
           ;; Without it smtpmail authenticates as a user it has no password
           ;; for, and the send fails at the server rather than in Emacs.
           ((and (stringp from) (string-match-p "rkr0k0r@gmail\\.com" from))
            (setq smtpmail-smtp-user "rkr0k0r@gmail.com"))
           (t
            (setq smtpmail-smtp-user "injoystickly@gmail.com")))))))

  (add-hook 'message-send-hook #'my-gnus-set-smtp-user-safe)

  (setq send-mail-function 'smtpmail-send-it
        message-send-mail-function 'smtpmail-send-it))

;; 7. Authentication Source Files
;; Decrypted by agenix at ACTIVATION, not by Emacs at read time.
;;
;; /run/agenix is tmpfs, and the secret is installed owner=r0k0r mode=0400
;; (features/emacs/nixos.nix, my.emacs.authinfoSecret) -- so this is a plain
;; readable netrc as far as auth-source is concerned. No gpg, no passphrase,
;; no pinentry, nothing to prompt: the whole "Decryption failed, Bad session
;; key" class of failure cannot occur here because nothing is decrypted in
;; this process.
;;
;; The ciphertext (age/authinfo.age) is committed to the PUBLIC flake repo,
;; which is the intended use of age -- the private identity lives at
;; /etc/agenix/identity.txt, outside the flake, and never enters the store.
;;
;; No fallback list: a second path only obscures which file a lookup used,
;; and on a host without agenix this should fail loudly rather than quietly
;; reading a stale copy.
(setq auth-sources '("/run/agenix/authinfo"))

;; ==========================================
;; 9. CONDA (optional install + REPL prefers global Python when inactive)
;; ==========================================
;; Doom `+python-executable-find' calls into conda.el even when no env is active (slow / errors if
;; conda binary missing). We advise it below to use `executable-find' first when neither venv nor
;; conda is activated. Append conda `bin' so `python3' stays Nix/system-first on PATH.

(let ((conda-home (expand-file-name "~/anaconda3")))
  (when (file-directory-p conda-home)
    (setq conda-anaconda-home conda-home)
    (let ((conda-bin (expand-file-name "bin" conda-home)))
      (when (file-directory-p conda-bin)
        (add-to-list 'exec-path conda-bin t)
        (setenv "PATH" (concat (getenv "PATH") path-separator conda-bin))))))

(defun my/+python-executable-find-with-fallback (orig-fn exe)
  "When no venv and no active conda env, use EXE from PATH before conda inference."
  (if (file-name-absolute-p exe)
      (funcall orig-fn exe)
    (let ((venv-root (bound-and-true-p python-shell-virtualenv-root))
          (conda-active (bound-and-true-p conda-env-current-path)))
      (if (or venv-root conda-active)
          (funcall orig-fn exe)
        (or (executable-find exe)
            (condition-case nil
                (funcall orig-fn exe)
              (error nil)))))))

;; ==========================================
;; 10. AUCTEX SETUP
;; ==========================================

(setq TeX-output-dir "build")

;; ==========================================
;; 11. KOREAN INPUT SETUP
;; ==========================================

(use-package! reverse-im
  :demand t
  :config
  (reverse-im-activate "korean-hangul")
  (setq reverse-im-input-methods '("korean-hangul"))
  (reverse-im-mode t))

(setenv "XMODIFIERS" "@im=none")
(setenv "GTK_IM_MODULE" "none")
(setenv "QT_IM_MODULE" "none")

(setq default-input-method "korean-hangul")

(map! :ni "M-`" #'toggle-input-method)

(setq auto-mode-alist
      (seq-filter (lambda (x) (stringp (car x))) auto-mode-alist))

;; ==========================================
;; 12. TRAMP FIX
;; ==========================================

(after! tramp
  ;; Also picks up PATH changes from direnv (envrc, below).
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path)

  ;; yulee's login shell is fish. TRAMP's `ssh' method has ssh start the LOGIN
  ;; shell and then sends one handoff line to exec into /bin/sh:
  ;;   exec env TERM='dumb' INSIDE_EMACS='...' HISTFILE=~/.tramp_history \
  ;;        PS1=///<hash> ... /bin/sh -i
  ;; fish records that before handing over, so ~/.local/share/fish/fish_history
  ;; fills with TRAMP internals (31 such entries when this was found). TRAMP's
  ;; own `tramp-histfile-override' does not help: it sets HISTFILE, which fish
  ;; does not use. fish's `fish_should_add_to_history' hook would, but it does
  ;; not exist until fish 4.0 (verified: never called on fish 3.7).
  ;;
  ;; `sshx' is the built-in answer -- its login args pass
  ;;   -o RemoteCommand="%l"
  ;; so ssh runs /bin/sh directly and fish never starts. TRAMP documents the
  ;; method as being for hosts "where the normal login shell is set up to ask
  ;; a number of questions when logging in", which is this case.
  ;;
  ;; Verified: fish history 652 entries before AND after, for both a direct
  ;; connection and the qas-dev container reached through yulee.
  ;;
  ;; PER-HOST. yulee gets sshx; victus-15 must NOT.
  ;;
  ;; sshx wedges victus-15 in sustained use. Caught in the act: Emacs at 96.3%
  ;; CPU and unresponsive, with exactly ONE child --
  ;;   ssh ... -t -t -o RemoteCommand=/bin/sh -i victus-15
  ;; -- 11 minutes old. Killing that single process took CPU to 0.0%
  ;; immediately, so Emacs was spinning on that connection and nothing else.
  ;; Every stall observed had a victus-15 connection present.
  ;;
  ;; Do not be fooled by a quick check: a one-shot `directory-files' on a
  ;; freshly opened /sshx:victus-15: succeeds in 1-2s, five times running. That
  ;; is what made an earlier attempt at this comment retract the finding. The
  ;; wedge needs a live buffer and sustained traffic (vc-registered, saves,
  ;; file-attributes), not a single round trip.
  ;;
  ;; The precise mechanism is still unproven -- plausibly the interactive
  ;; /bin/sh (NixOS bash-interactive here, dash on yulee) plus -t -t, but that
  ;; is a hypothesis, not a demonstrated cause. The scoping is justified by the
  ;; reproduction above regardless.
  ;;
  ;; Cost: victus-15 keeps writing TRAMP lines into its own fish_history.
  ;; That is the lesser problem.
  (add-to-list 'tramp-default-method-alist '("\\`yulee\\'" nil "sshx"))

  ;; Bound the cost of a sleeping host or any future wedge: the default 60s is
  ;; long enough to look like a hard freeze when a saved workspace restores a
  ;; remote buffer on frame creation.
  (setq tramp-connection-timeout 10)
  ;; The container is reached through yulee; proxy over sshx too. This also
  ;; replaces the ad-hoc proxy TRAMP creates when you type an explicit
  ;; /ssh:yulee|docker:qas-dev: path (those are runtime-only by default, since
  ;; `tramp-save-ad-hoc-proxies' is nil).
  (add-to-list 'tramp-default-proxies-alist '("\\`qas-dev\\'" nil "/sshx:yulee:")))

(use-package! envrc
  :config
  (envrc-global-mode)
  ;; This is the critical line for your TRAMP / SSH setup
  (setq envrc-remote-enable t))

;; ==========================================
;; Machine-local overrides (optional, Home Manager–friendly)
;; ==========================================
;; Editable via Home Manager: ~/.config/home-manager/doom-machine-local.el (declared in home-r0k0r.nix).
(let* ((xdg (or (getenv "XDG_CONFIG_HOME") (expand-file-name "~/.config")))
       (hm-local (expand-file-name "home-manager/doom-machine-local.el" xdg)))
  (when (file-readable-p hm-local)
    (load hm-local nil 'nomessage)))

;; Arduino: enable arduino-cli keybindings/compilation in .ino buffers.
(use-package! arduino-cli-mode
  :hook (arduino-mode . arduino-cli-mode)
  :custom
  (arduino-cli-warnings 'all)
  (arduino-cli-verify t))

;; `project--write-project-list' does not create the directory it writes into,
;; so a fresh state directory turns every project visit into
;; "Opening output file: No such file or directory".  Make it exist.
(defun +ensure-project-list-directory (&rest _)
  (when-let* ((file (bound-and-true-p project-list-file))
              (dir (file-name-directory file)))
    (unless (file-directory-p dir)
      (ignore-errors (make-directory dir t)))))

(advice-add 'project--write-project-list :before #'+ensure-project-list-directory)
