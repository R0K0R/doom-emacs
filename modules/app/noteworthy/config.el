;;; app/noteworthy/config.el -*- lexical-binding: t; -*-

(require 'noteworthy)

(defvar +noteworthy-terminal-cmd '("/bin/distrobox-host-exec" "/usr/bin/fish")
  "Command to run in the Noteworthy terminal.")

(use-package! dtrt-indent
  :after typst-ts-mode
  :config
  ;; 1. Enable dtrt-indent whenever typst-ts-mode starts
  (add-hook 'typst-ts-mode-hook #'dtrt-indent-mode)
  
  ;; 2. (Optional) Help dtrt-indent recognize Typst syntax
  ;; Mapping it to 'javascript' usually works well for braces {} and brackets []
  (add-to-list 'dtrt-indent-hook-mapping-list '(typst-ts-mode javascript)))

(use-package! treesit
  :config
  (add-to-list 'treesit-language-source-alist
               '(typst "https://github.com/uben0/tree-sitter-typst")))

(use-package! treesit-auto
  :config
  (setq treesit-auto-install 'prompt)
  (treesit-auto-add-to-auto-mode-alist 'all))

(use-package! typst-preview
  :config
  (setq typst-preview-executable "tinymist")
  (setq typst-preview-partial-rendering t))

;; Register Typst language ID so lsp-mode can route .typ buffers to Tinymist
(after! lsp-mode
  (add-to-list 'lsp-language-id-configuration '(typst-ts-mode . "typst")))

;; Register Tinymist as an lsp-mode client for Typst
(after! lsp-mode
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (lambda () (list "tinymist" "lsp")))
    :major-modes '(typst-ts-mode)
    :server-id 'tinymist
    :priority 1
    :initialization-options
    (lambda ()
      (let* ((root (or (bound-and-true-p noteworthy-project-root)
                       (when-let* ((proj (project-current)))
                         (project-root proj))
                       default-directory))
             (main (or (bound-and-true-p noteworthy-master-file)
                       (let ((f (expand-file-name "main.typ" root)))
                         (when (file-exists-p f) f)))))
        (if main
            (list :rootPath root :exportOpts (list :input main))
          (list :rootPath root)))))))

;; Start LSP automatically in Typst files
(add-hook 'typst-ts-mode-hook #'lsp-deferred)

;; Ensure Flycheck uses LSP diagnostics (not naive CLI checkers)
(after! lsp-mode
  (setq lsp-diagnostics-provider :flycheck))

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

;; Font: Required for VTerm/Fish prompt glyphs
(setq doom-font (font-spec :family "JetBrainsMonoNL Nerd Font" :size 15 :weight 'semi-light)
      doom-variable-pitch-font (font-spec :family "JetBrainsMonoNL Nerd Font" :size 15))

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

;;(use-package! noteworthy-collab
;;  :commands (noteworthy-remote-init noteworthy-collab-disconnect noteworthy-collab-status)
;;  :config
;;  ;; Default server URL
;;  (setq noteworthy-collab-server-url "ws://localhost:8000/ws/emacs")
;;  
;;  ;; Your display name for collaboration
;;  (setq noteworthy-collab-user-name user-login-name)
;;  
;;  ;; Terminal command for remote sessions (same as local)
;;  (setq noteworthy-collab-terminal-cmd +noteworthy-terminal-cmd)
;;  
;;  ;; Preview URL (set this to your port-forwarded tinymist URL)
;;  ;; ssh -L 23625:localhost:23625 yourserver
;;  ;; (setq noteworthy-collab-preview-url "http://localhost:23625")
;;  )
;;
;;;; Keybindings for collaboration
;;(map! :leader
;;      :prefix ("n" . "noteworthy")
;;      :desc "Remote init" "r" #'noteworthy-remote-init
;;      :desc "Disconnect" "d" #'noteworthy-collab-disconnect
;;      :desc "Status" "s" #'noteworthy-collab-status
;;      :desc "Toggle log" "l" #'noteworthy-collab-toggle-log)
;;
