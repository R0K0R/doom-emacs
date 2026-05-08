;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(defun my/path-force-first-component (directory)
  "Ensure DIRECTORY appears once and is first on `PATH', and prepend `exec-path'."
  ;; Distrobox shims (`/usr/local/bin') must precede conda/Anaconda shadows.
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

;; VTerm shell
(setq vterm-shell "distrobox-host-exec fish")

;; Doom enables `hide-mode-line-mode` in vterm, DAP REPL, terminals, etc.—undo that for a persistent modeline.
(defun my/show-mode-line-maybe ()
  (when (bound-and-true-p hide-mode-line-mode)
    (hide-mode-line-mode -1)))

(after! vterm
  (remove-hook 'vterm-mode-hook #'hide-mode-line-mode))

(after! dape
  (remove-hook 'dape-repl-mode-hook #'hide-mode-line-mode))

;; Inferior Python, ielm, `M-x compile`, and other comint-derived REPLs.
(add-hook 'comint-mode-hook #'my/show-mode-line-maybe t)

;; If you enable :term {shell,term,eshell}, these remove Doom’s default hiding there too.
(after! shell (remove-hook 'shell-mode-hook #'hide-mode-line-mode))
(after! term (remove-hook 'term-mode-hook #'hide-mode-line-mode))
(after! eshell (remove-hook 'eshell-mode-hook #'hide-mode-line-mode))

;; clipetty
(use-package! clipetty
  :hook (after-init . global-clipetty-mode))

;; xwidgets
(when (featurep 'xwidget-internal)
  (setq browse-url-browser-function #'xwidget-webkit-browse-url))

;; ==========================================
;; 3. PYTHON & REPL (Fixes VS Code Corruption)
;; ==========================================
(after! python
  (setenv "TERM_PROGRAM" "dumb")
  (setenv "TERM" "dumb")
  (setenv "VSCODE_IPC_HOOK_CLI" nil)
  (setenv "VSCODE_SHELL_INTEGRATION" nil)
  (setq python-shell-interpreter "python3"
        python-shell-interpreter-args "-i"))
  (setenv "QT_QPA_PLATFORM" "xcb")
  (setenv "QT_AUTO_SCREEN_SCALE_FACTOR" "1")

;; ==========================================
;; 4. LSP & INTELLIGENCE (BasedPyright + Ruff)
;; ==========================================

(after! lsp-mode
  (setq lsp-completion-provider :capf
        lsp-prefer-capf t)

  ;; 1. THE FIX: Allow all valid clients, and STOP disabling pyright
  (setq lsp-enabled-clients nil)
  (setq lsp-disabled-clients '(pylsp pyls ruff-lsp semgrep-ls ty-ls mspyls))

  (setq lsp-modeline-code-actions-enable t
        lsp-inlay-hint-enable t)

  (add-to-list 'lsp-language-id-configuration '(python-ts-mode . "python")))

;; 2. BasedPyright: settings + dependency path
(after! lsp-pyright
  (setq lsp-pyright-langserver-command "basedpyright"
        lsp-pyright-type-checking-mode "standard")
  ;; `lsp-dependency' is fixed when lsp-pyright loads (frozen at `pyright-langserver');
  ;; re-register after `setq' above. Prefer `basedpyright-langserver' on PATH / ~/.local.
  ;; Install inside the Emacs distrobox: `sudo dnf install -y python3-pip' then
  ;; `python3 -m pip install --user basedpyright' — same ~/.local/bin as the host HOME,
  ;; but Fedora's /usr/bin/python3 + ~/.local/lib/python3.11 (no vfork ENOENT vs pipx/py314).
  (lsp-dependency 'pyright
    `(:system ,(or (executable-find "basedpyright-langserver" t)
                  (let ((p (expand-file-name "~/.local/bin/basedpyright-langserver")))
                    (when (file-executable-p p) p))
                  "basedpyright-langserver"))
    `(:npm :package "basedpyright" :path "basedpyright-langserver")))

;; Ensure lsp-mode attaches to tree-sitter Python
(defun my-python-setup-h ()
  (lsp-deferred))

(add-hook 'python-mode-hook #'my-python-setup-h)
(add-hook 'python-ts-mode-hook #'my-python-setup-h)

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

;; ==========================================
;; 7. FOOT TUI IMAGES
;; ==========================================

;; 1. Force Emacs to allow image/PDF processing in the TUI
(setq mml-smime-use 'epg) ; unrelated but helps with some rendering errors

;; 2. The critical hack for pdf-tools in terminal
(after! pdf-tools
  (setq pdf-view-use-scaling t
        pdf-view-use-imagemagick t)
  ;; This prevents pdf-tools from demanding a GUI frame
  (advice-add #'pdf-info-renderpage :around
              (lambda (orig-fun &rest args)
                (if (display-graphic-p)
                    (apply orig-fun args)
                  ;; If in TUI, we force it to treat the terminal as capable
                  (let ((display-graphic-p (lambda () t)))
                    (apply orig-fun args))))))

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
;; 9. ANACONDA SETUP
;; ==========================================

(let ((conda-path "/home/r0k0r/anaconda3/bin/"))
  (setenv "PATH" (concat conda-path ":" (getenv "PATH")))
  (add-to-list 'exec-path conda-path))

(setq conda-anaconda-home "/home/r0k0r/anaconda3/")

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
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

(use-package! envrc
  :config
  (envrc-global-mode)
  ;; This is the critical line for your TRAMP / SSH setup
  (setq envrc-remote-enable t))

(after! python
  ;; Still disable this—it's the #1 cause of TRAMP hangs
  (setq python-shell-completion-native-enable nil))

(after! tramp
  ;; Ensure TRAMP picks up the path changes from direnv
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

;; ==========================================
;; 13. Flutter (Distrobox: Fedora container + Arch host)
;; ==========================================
;;
;; Arch dart under /run/host/opt/dart-sdk is linked against glibc 2.38+; Fedora 38 in
;; emacs-build-fedora only has 2.37.  Emacs execs that ELF in the container namespace →
;; immediate failure (see *lsp-log* / shell: `/run/host/opt/dart-sdk/bin/dart --version`).
;; /usr/local/bin/dart and flutter are distrobox-host-exec shims → analysis server runs on
;; the host.  Treat /usr/local as the SDK *root* so lsp-dart resolves bin/dart and
;; bin/flutter to those scripts instead of host ELF paths.
;;
;; The analyzer returns URIs like file:///usr/lib/flutter/... (host paths).  Inside the
;; container those files live under /run/host/... .  Without remapping, xref/LSP jump and
;; peek cannot open SDK sources (“No xref definition”).  Map both directions below.

(after! lsp-dart
  ;; Default order is `(lsp-root closest-pubspec)`. If the LSP workspace is a parent folder
  ;; without pubspec.yaml (repo root with `flutter_demo/` inside), `lsp-workspace-root' wins,
  ;; `lsp-dart-flutter-project-p` is nil, and test runs use Dart's test runner instead of
  ;; `flutter test --machine', so *LSP Dart tests* stays on "Spawning test process...".
  (setq lsp-dart-project-root-discovery-strategies '(closest-pubspec lsp-root))
  ;; lsp-dart's Run/Debug overlays above main/tests (custom overlays, not lsp-mode lens).
  (setq lsp-dart-main-code-lens nil
        lsp-dart-test-code-lens nil)
  ;; Do not turn on `lsp-dart-dap-mode' when a DAP session is created (after-save /
  ;; dap-output buffer tweaks); you still have flutter.el and `flutter-run' commands.
  (remove-hook 'dap-session-created-hook #'lsp-dart-dap--enable-mode)
  (remove-hook 'dap-terminated-hook #'lsp-dart-dap--disable-mode))

(defun my/distrobox-arch-host-flutter-sdk-p ()
  "Host Flutter SDK is mounted under /run/host (Distrobox), not at /usr/lib/flutter."
  (and (file-exists-p "/run/host/usr/lib/flutter/packages/flutter/lib/material.dart")
       (not (file-exists-p "/usr/lib/flutter/packages/flutter/lib/material.dart"))))

(defun my/lsp--uri-to-path-distrobox-aov (orig-fn uri)
  (let ((path (funcall orig-fn uri)))
    (if (my/distrobox-arch-host-flutter-sdk-p)
        (cond ((string-prefix-p "/usr/lib/flutter/" path)
               (concat "/run/host" path))
              ((string-prefix-p "/opt/dart-sdk/" path)
               (concat "/run/host" path))
              (t path))
      path)))

(defun my/lsp--path-to-uri-1-distrobox-aov (orig-fn path)
  (if (null path)
      (funcall orig-fn path)
    (let ((path
           (if (my/distrobox-arch-host-flutter-sdk-p)
               (cond ((string-prefix-p "/run/host/usr/lib/flutter/" path)
                      (substring path (length "/run/host")))
                     ((string-prefix-p "/run/host/opt/dart-sdk/" path)
                      (substring path (length "/run/host")))
                     (t path))
             path)))
      (funcall orig-fn path))))

(when (file-directory-p "/run/host/opt/dart-sdk")
  (after! lsp-dart
    (setq lsp-dart-sdk-dir "/usr/local"
          lsp-dart-flutter-sdk-dir "/usr/local"))
  (after! lsp-mode
    (when (file-exists-p "/run/host/usr/lib/flutter/packages/flutter/lib/material.dart")
      (advice-add 'lsp--uri-to-path :around #'my/lsp--uri-to-path-distrobox-aov)
      (advice-add 'lsp--path-to-uri-1 :around #'my/lsp--path-to-uri-1-distrobox-aov))))
