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

;; Dashboard banner: fastfetch's output, run afresh each time the dashboard
;; is shown.  It takes ~0.3 s, too long to block on for every switch to the
;; dashboard, so the banner draws the last run's output at once and a new run
;; redraws it when it finishes.  fastfetch comes from the Nix emacs feature.
(setq fancy-splash-image nil)           ; the same text banner in GUI frames

(defvar my/fastfetch-program "fastfetch")
(defvar my/fastfetch--raw nil "The last run's output, as fastfetch printed it.")
(defvar my/fastfetch--banner nil "The last run's output, colored, for the dashboard.")
(defvar my/fastfetch--process nil)
(defvar my/fastfetch--redrawing nil
  "Non-nil while a finished run redraws the dashboard, so it starts no new run.")

(defun my/fastfetch--colorize (raw)
  "RAW, fastfetch's ANSI-colored output, with the colors as faces."
  (let* ((s (ansi-color-apply raw))
         (i 0))
    ;; ansi-color leaves them in `font-lock-face', which shows only with
    ;; font-lock on, and the dashboard buffer has it off.
    (while (< i (length s))
      (let ((next (next-single-property-change i 'font-lock-face s (length s)))
            (face (get-text-property i 'font-lock-face s)))
        (when face (put-text-property i next 'face face s))
        (setq i next)))
    ;; Newlines only: the palette rows at the end are colored spaces.
    (string-trim-right s "\n+")))

(defun my/fastfetch-refresh ()
  "Run fastfetch, and redraw the dashboard with its output when it changed."
  (when (and (executable-find my/fastfetch-program)
             (not (process-live-p my/fastfetch--process)))
    (let ((buf (generate-new-buffer " *fastfetch*"))
          ;; The dashboard may sit in a remote directory; fastfetch is local.
          (default-directory temporary-file-directory))
      (setq my/fastfetch--process
            (make-process
             :name "fastfetch" :buffer buf :noquery t :connection-type 'pipe
             ;; --pipe lays the info beside the logo with spaces, not cursor
             ;; movement; `false' keeps the colors anyway.
             :command (list my/fastfetch-program "--pipe" "false")
             :sentinel
             (lambda (proc _event)
               (unless (process-live-p proc)
                 (let ((out (with-current-buffer buf (buffer-string))))
                   (kill-buffer buf)
                   (when (and (zerop (process-exit-status proc))
                              (not (equal out my/fastfetch--raw)))
                     (setq my/fastfetch--raw out
                           my/fastfetch--banner (my/fastfetch--colorize out))
                     (when (fboundp '+dashboard-reload)
                       (let ((my/fastfetch--redrawing t))
                         (+dashboard-reload t))))))))))))

(defun my/dashboard-fastfetch-banner ()
  "The dashboard banner: fastfetch's last output, refreshed in the background."
  (unless my/fastfetch--redrawing
    (my/fastfetch-refresh))
  my/fastfetch--banner)

(setq +dashboard-ascii-banner-fn #'my/dashboard-fastfetch-banner)

;; Noteworthy courses at the top of the dashboard menu, above Doom's own.
(defvar my/dashboard-noteworthy-sections
  '(("General Physics I"
     :icon (nerd-icons-mdicon "nf-md-atom" :face '+dashboard-menu-title)
     :action physics1-noteworthy-init)
    ("Calculus II (collab)"
     :icon (nerd-icons-mdicon "nf-md-sigma" :face '+dashboard-menu-title)
     :action noteworthy-collab-calculus2)
    ("Open a Noteworthy project"
     :icon (nerd-icons-mdicon "nf-md-notebook_edit_outline" :face '+dashboard-menu-title)
     :action noteworthy-init))
  "Dashboard menu entries for the Noteworthy courses.")

(when (boundp '+dashboard-menu-sections)
  (setq +dashboard-menu-sections
        (append my/dashboard-noteworthy-sections
                (cl-remove-if (lambda (s) (assoc (car s) my/dashboard-noteworthy-sections))
                              +dashboard-menu-sections))))

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
              (cons #'my-lsp-completion-capf
                    (delq #'yasnippet-capf
                          (delq #'my-lsp-completion-capf
                                (delq #'lsp-completion-at-point completion-at-point-functions))))))

;; No snippets in the completion popup.  Snippets still expand by key (TAB)
;; and the auto-expanding ones still fire as you type; they only stop
;; showing up as Corfu candidates next to real completions.
(remove-hook 'yas-minor-mode-hook #'+corfu-add-yasnippet-capf-h)

(add-hook 'python-ts-mode-hook #'force-corfu-pipes-h 'append)
(add-hook 'python-mode-hook #'force-corfu-pipes-h 'append)
(add-hook 'lsp-completion-mode-hook #'force-corfu-pipes-h)

;; nixd option completion. nixd 2.x no longer reads .nixd.json: it asks the
;; client for its "nixd" settings (and only evaluates option sets it gets that
;; way -- a --config on the command line is replaced by the client's answer).
;; So hand it the project's .nixd.json anyway, read when nixd asks: lsp-mode
;; calls a function-valued setting at request time, inside the requesting
;; workspace, so each project gets its own file and the file stays the per-repo
;; source of truth (flakes/nixos keeps its option exprs there). No .nixd.json ->
;; nil -> lsp-mode omits the key and nixd uses its defaults.
(defun my/nixd-json (&rest path)
  "The value at PATH (symbols) in the current LSP workspace's .nixd.json."
  (when-let* ((ws lsp--cur-workspace)
              (file (expand-file-name ".nixd.json" (lsp--workspace-root ws)))
              ((file-readable-p file))
              (v (json-parse-string
                  (with-temp-buffer (insert-file-contents file) (buffer-string))
                  :object-type 'alist :null-object nil)))
    (dolist (k path v) (setq v (alist-get k v)))))

(after! lsp-nix
  (setq lsp-nix-nixd-nixpkgs-expr (lambda () (my/nixd-json 'nixpkgs 'expr))
        lsp-nix-nixd-nixos-options-expr (lambda () (my/nixd-json 'options 'nixos 'expr))
        lsp-nix-nixd-home-manager-options-expr
        (lambda () (my/nixd-json 'options 'home-manager 'expr))))

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

(defvar physics1-dropbox (expand-file-name "~/KSA/General_Physics_I/dropbox/")
  "General Physics I class materials, the PDFs usually opened beside the notes.")

(defvar physics1-textbook
  (expand-file-name "~/KSA/General_Physics_I/textbook/redirection.epub")
  "General Physics I textbook, University Physics 3rd ed., read in nov.el.")

(defun physics1--read-material ()
  "Ask for the material to open beside the notes.
The class PDFs newest first, so RET takes the latest one, then the textbook."
  (let* ((pdfs (sort (directory-files physics1-dropbox t "\\.pdf\\'")
                     (lambda (a b)
                       (time-less-p (file-attribute-modification-time (file-attributes b))
                                    (file-attribute-modification-time (file-attributes a))))))
         (textbook "Textbook (University Physics)")
         (names (append (mapcar #'file-name-nondirectory pdfs) (list textbook)))
         (choice (completing-read
                  "Open beside the notes: "
                  (lambda (str pred action)
                    (if (eq action 'metadata)
                        '(metadata (display-sort-function . identity))
                      (complete-with-action action names str pred)))
                  nil t nil nil (car names))))
    (if (equal choice textbook)
        physics1-textbook
      (expand-file-name choice physics1-dropbox))))

(defun physics1-noteworthy-init (material)
  "Initialize General Physics I KSA Course, with MATERIAL beside the notes.
Interactively, pick it from the class PDFs or the textbook."
  (interactive (list (physics1--read-material)))
  (noteworthy-init (expand-file-name "~/KSA/General_Physics_I/noteworthy/") material))

;; EPUBs read in nov.el.  Two things make a big one -- the physics textbook
;; is 1.1 GB, mostly images -- slow to open, both fixed here:
;;
;; - nov unzips the book into a fresh temporary directory on every open and
;;   deletes it on close; for this one that is 11 s of Emacs frozen in
;;   `call-process' each time.  It is unzipped once instead, into a cache
;;   keyed by the file's path, size and modification time, and reused.
;; - `find-file' reads the whole file into the buffer before the major mode
;;   runs, and nov throws that away, working from the unzipped copy.  An
;;   EPUB is visited without reading it.
(defvar my/nov-cache-directory (expand-file-name "nov/" (or (getenv "XDG_CACHE_HOME") "~/.cache"))
  "Where EPUBs are unzipped, once each, for nov.el.")

(defun my/nov--cache-dir (file)
  "The directory FILE is unzipped into, named for its path, size and mtime."
  (let ((attrs (file-attributes (file-truename file))))
    (expand-file-name
     (md5 (format "%s|%s|%s" (file-truename file)
                  (file-attribute-size attrs)
                  (format-time-string "%s" (file-attribute-modification-time attrs))))
     my/nov-cache-directory)))

(defun my/nov--initialize-cached (orig path)
  "Point nov at PATH's cached unzipped copy, unzipping it only the first time.
ORIG is `nov--initialize-temp-dir'."
  (let* ((dir (my/nov--cache-dir path))
         (done (expand-file-name ".complete" dir)))
    (unless (file-exists-p done)
      (message "Unzipping %s once for nov..." (file-name-nondirectory path))
      (when (file-directory-p dir) (delete-directory dir t))
      (make-directory my/nov-cache-directory t)
      ;; Let nov unzip and validate into its own temporary directory as usual,
      ;; then take that directory over as the cache.
      (funcall orig path)
      (rename-file (directory-file-name nov-work-dir) dir)
      (write-region "" nil done nil 'silent))
    (setq nov-work-dir dir)))

(defun my/nov--keep-cache (orig &rest args)
  "Run ORIG, `nov-clean-up', without deleting a cached unzipped copy.
It still saves the reading position."
  (if (and (bound-and-true-p nov-work-dir)
           (file-in-directory-p nov-work-dir my/nov-cache-directory))
      (cl-letf (((symbol-function 'delete-directory) #'ignore))
        (apply orig args))
    (apply orig args)))

(defun my/nov--visit-without-reading (orig filename &rest args)
  "Visit a local EPUB FILENAME in nov without reading it into the buffer.
ORIG and ARGS are `find-file-noselect' and the rest of its arguments."
  (let ((file (expand-file-name filename)))
    (if (or (not (string-match-p "\\.epub\\'" file))
            (file-remote-p file)
            (not (file-readable-p file))
            (find-buffer-visiting file)
            (not (require 'nov nil t)))
        (apply orig filename args)
      (let ((buf (create-file-buffer file)))
        (condition-case err
            (with-current-buffer buf
              (setq buffer-file-name file
                    buffer-file-truename (abbreviate-file-name (file-truename file))
                    default-directory (file-name-directory file))
              (set-visited-file-modtime)
              (nov-mode)
              buf)
          (error
           (kill-buffer buf)
           (message "nov could not open %s: %s" file (error-message-string err))
           (apply orig filename args)))))))

;; The textbook's equations are MathML, which shr does not know: it runs each
;; one's characters together, `K = 1/2 m v^2' coming out as `K=12mv2'.  They
;; are written out as Typst-style math instead, which reads the same in a
;; terminal frame.
(defconst my/nov-mathml--spaced-ops
  '("=" "≈" "≠" "<" ">" "≤" "≥" "+" "−" "-" "±" "∓" "→" "⇒" "⇔" "×" "·" "≡" "∝" "≅" "∼" "∈")
  "Operators written with a space either side.")

(defconst my/nov-mathml--accents
  '(("→" . "arrow") ("⃗" . "arrow") ("^" . "hat") ("ˆ" . "hat") ("¯" . "overline")
    ("‾" . "overline") ("˙" . "dot") ("." . "dot") ("¨" . "dot.double") ("~" . "tilde") ("˜" . "tilde"))
  "MathML accent characters and the Typst accent each is written as.")

(defun my/nov-mathml--kids (node)
  (seq-remove (lambda (k) (and (stringp k) (string-blank-p k))) (dom-children node)))

(defun my/nov-mathml--join (parts)
  "Concatenate PARTS, with a space where two would otherwise run together."
  (let ((out ""))
    (dolist (p parts out)
      (setq out (if (and (> (length out) 0) (> (length p) 0)
                         (string-match-p "[[:alnum:])]\\'" out)
                         (string-match-p "\\`[[:alnum:](∑∫∏∮√∂∇]" p))
                    (concat out " " p)
                  (concat out p))))))

(defun my/nov-mathml--group (s)
  "S as an operand: bare when it is a single token, else in parentheses."
  (if (string-match-p "\\`\\(?:[[:alnum:].′⊥∞∥*]+\\|([^()]*)\\|[[:alnum:]]+([^()]*)\\)\\'" s)
      s
    (format "(%s)" s)))

(defun my/nov-mathml--lin (node)
  "NODE, a MathML element, as a line of Typst-like math."
  (if (stringp node)
      (string-trim node)
    (let* ((kids (my/nov-mathml--kids node))
           (lin (lambda (i) (my/nov-mathml--lin (nth i kids))))
           (all (lambda () (my/nov-mathml--join (mapcar #'my/nov-mathml--lin kids)))))
      (pcase (dom-tag node)
        ((or 'mi 'mn 'mtext 'ms) (string-trim (dom-texts node "")))
        ('mo (let ((o (string-trim (dom-texts node ""))))
               (if (member o my/nov-mathml--spaced-ops) (concat " " o " ") o)))
        ('mspace " ")
        ('mfrac (format "%s/%s" (my/nov-mathml--group (funcall lin 0))
                        (my/nov-mathml--group (funcall lin 1))))
        ('msup (format "%s^%s" (my/nov-mathml--group (funcall lin 0))
                       (my/nov-mathml--group (funcall lin 1))))
        ((or 'msub 'munder)
         (format "%s_%s" (funcall lin 0) (my/nov-mathml--group (funcall lin 1))))
        ((or 'msubsup 'munderover)
         (format "%s_%s^%s" (funcall lin 0) (my/nov-mathml--group (funcall lin 1))
                 (my/nov-mathml--group (funcall lin 2))))
        ('mover
         (let ((accent (cdr (assoc (string-trim (dom-texts (nth 1 kids) "")) my/nov-mathml--accents))))
           (if accent
               (format "%s(%s)" accent (funcall lin 0))
             (format "%s^%s" (funcall lin 0) (my/nov-mathml--group (funcall lin 1))))))
        ('msqrt (format "sqrt(%s)" (funcall all)))
        ('mroot (format "root(%s, %s)" (funcall lin 1) (funcall lin 0)))
        ('mfenced
         (concat (or (dom-attr node 'open) "(")
                 (mapconcat #'my/nov-mathml--lin kids (or (dom-attr node 'separators) ", "))
                 (or (dom-attr node 'close) ")")))
        ('mtable (mapconcat #'my/nov-mathml--lin kids "\n"))
        (_ (funcall all))))))

(defun my/nov-mathml-text (dom)
  "DOM, a <math> element, as lines of Typst-like math."
  (mapconcat (lambda (l) (replace-regexp-in-string "  +" " " (string-trim l)))
             (split-string (my/nov-mathml--lin dom) "\n")
             "\n"))

(defun my/nov-render-math (dom)
  "Render DOM, a MathML <math> element, as Typst-like text.
shr does not know MathML and runs an equation's characters together."
  (let ((text (propertize (my/nov-mathml-text dom) 'face 'font-lock-constant-face)))
    (if (equal (dom-attr dom 'display) "block")
        (progn
          (shr-ensure-newline)
          (insert (mapconcat (lambda (l) (concat "    " l)) (split-string text "\n") "\n"))
          (shr-ensure-newline))
      (shr-insert (replace-regexp-in-string "\n" "; " text)))))

;; Reading positions: nov keeps them under `user-emacs-directory', which in
;; this Doom is a cache directory.  They are data, kept with Doom's own.
(setq nov-save-place-file
      (expand-file-name "nov-places" (if (boundp 'doom-data-dir) doom-data-dir
                                       (or (getenv "XDG_DATA_HOME") "~/.local/share"))))

(add-to-list 'auto-mode-alist '("\\.epub\\'" . nov-mode))
(advice-add 'find-file-noselect :around #'my/nov--visit-without-reading)
(with-eval-after-load 'nov
  (advice-add 'nov--initialize-temp-dir :around #'my/nov--initialize-cached)
  (advice-add 'nov-clean-up :around #'my/nov--keep-cache)
  (add-to-list 'nov-shr-rendering-functions '(math . my/nov-render-math)))

(defun physics1-noteworthy-no-pdf ()
  "Initialize General Physics I KSA Course without a PDF"
  (interactive)
  (let ((project-dir (expand-file-name "~/KSA/General_Physics_I/noteworthy/")))
    (noteworthy-init project-dir nil)))

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
