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
  (setq gnus-secondary-select-methods
        '((nnimap "gmail"
                  (nnimap-address "imap.gmail.com")
                  (nnimap-server-port "imaps")
                  (nnimap-stream ssl)
                  (nnimap-authinfo-file "~/.authinfo.gpg"))
          (nnimap "ksa"
                  (nnimap-address "imap.gmail.com")
                  (nnimap-server-port "imaps")
                  (nnimap-stream ssl)
                  (nnimap-authinfo-file "~/.authinfo.gpg"))
          (nntp "eternal-september"
                (nntp-address "news.eternal-september.org"))
          (nntp "solani"
                (nntp-address "news.solani.org"))))
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
         (t
          (save-excursion (message-replace-header "From" "R0K0R Lee <injoystickly@gmail.com>")))))))

  (add-hook 'message-setup-hook #'my-doom-gnus-header-fix-safe)

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
           (t
            (setq smtpmail-smtp-user "injoystickly@gmail.com")))))))

  (add-hook 'message-send-hook #'my-gnus-set-smtp-user-safe)

  (setq send-mail-function 'smtpmail-send-it
        message-send-mail-function 'smtpmail-send-it))

;; 7. Authentication Source Files
(setq auth-sources '("~/.authinfo.gpg" "~/.authinfo" "~/.netrc"))

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
;; 13. Flutter / Dart LSP
;; ==========================================

(after! lsp-dart
  ;; Emacs daemon on NixOS often lacks profile PATH, so lsp-dart cannot find flutter/dart.
  (unless lsp-dart-flutter-sdk-dir
    (setq lsp-dart-flutter-sdk-dir
          (or (getenv "FLUTTER_ROOT")
              (-some-> (executable-find "flutter")
                file-truename
                (locate-dominating-file "bin")
                file-truename)
              (-some-> (format "/etc/profiles/per-user/%s/bin/flutter" (user-login-name))
                expand-file-name
                (and (file-exists-p it) (file-truename it))
                (locate-dominating-file "bin")
                file-truename))))
  ;; Default order is `(lsp-root closest-pubspec)`. If the LSP workspace is a parent folder
  ;; without pubspec.yaml (repo root with `flutter_demo/` inside), `lsp-workspace-root' wins,
  ;; `lsp-dart-flutter-project-p` is nil, and test runs use Dart's test runner instead of
  ;; `flutter test --machine', so *LSP Dart tests* stays on "Spawning test process...".
  (setq lsp-dart-project-root-discovery-strategies '(closest-pubspec lsp-root))
  (setq lsp-dart-main-code-lens nil
        lsp-dart-test-code-lens nil)
  (remove-hook 'dap-session-created-hook #'lsp-dart-dap--enable-mode)
  (remove-hook 'dap-terminated-hook #'lsp-dart-dap--disable-mode))

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
