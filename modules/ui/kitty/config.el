;;; ui/kitty/config.el -*- lexical-binding: t; -*-

;; Images, the Typst preview and PDFs inside `emacs -nw' in Kitty, through
;; kitty-graphics.  It is my fork (R0K0R/kitty-graphics.el, see packages.el):
;; the fixes live there -- popups over images, the browser following its
;; window, the cursor staying put while casty paints, child-frame flicker,
;; big PDFs, images surviving screen clears, a hidden browser actually
;; hiding.  What stays here is how I use it.
;;
;; The Emacs wrapper from the Nix emacs feature gives Emacs a Kitty terminfo
;; entry whose `clear' keeps images (see features/emacs/home.nix).

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

;; The mouse, in every terminal frame.  Emacs 31 turns `xterm-mouse-mode' on by
;; itself only after identifying the terminal from its XTVERSION reply, and
;; waits for that reply only briefly.  Under kitty-graphics' own start-up
;; probing the reply comes late -- "No catch for tag: result, kitty(0.48.2)"
;; at start-up -- so the mouse was never enabled: clicks became Kitty's text
;; selection, and the preview browser got no clicks or wheel at all.  Doom's
;; :os tty does exactly this before Emacs 31 and leaves it to the detection
;; from 31 on.
(add-hook 'tty-setup-hook #'xterm-mouse-mode)
;; ...and now, for the frame Emacs started in: Doom loads this file after that
;; frame's terminal was already set up, so the hook above never runs for it --
;; a real-Kitty test showed `xterm-mouse-mode' still nil with only the hook.
;; The hook stays for terminals opened later (`emacsclient -t').
(when (and (not noninteractive) (eq (framep (selected-frame)) t))
  (xterm-mouse-mode 1))

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

;; The browser's refit and restart keys (kitty-graphics-browser-fit, -restart)
;; are in its keymap, but the browser buffer is in evil's normal state, where
;; both keys are taken.
(map! :after kitty-graphics
      :map kitty-graphics-browser-mode-map
      :n "=" #'kitty-graphics-browser-fit
      :n "R" #'kitty-graphics-browser-restart)

;; Refit the preview once a Noteworthy layout has opened it.  The layout sizes
;; its windows after the preview starts, and a remote one opens the preview
;; only once its tunnel is up, so a fit at the end of the init itself would
;; run before there is anything to fit.  Instead, the end of `noteworthy-init'
;; and `noteworthy-remote-init' waits for the browser opened after it to
;; connect, gives the layout a moment to settle, and fits it then.
(defvar my/kitty--browse-count 0
  "How many times `kitty-graphics-browse' has run.
Tells the browser an init opened from one that was already there.")

(defun my/kitty--count-browse (&rest _)
  "Count a `kitty-graphics-browse'."
  (cl-incf my/kitty--browse-count))

(advice-add 'kitty-graphics-browse :before #'my/kitty--count-browse)

(defun my/kitty--fit-when-ready (since &optional tries)
  "Fit the Kitty browser opened after browse number SINCE, once it is connected.
Checks every half second, TRIES so far, for up to a minute."
  (let* ((tries (or tries 0))
         (buf (get-buffer "*kitty-browser*"))
         (ready (and buf
                     (> my/kitty--browse-count since)
                     (buffer-local-value 'kitty-graphics--browser-ipc-connection buf)
                     (get-buffer-window buf t))))
    (cond
     (ready
      ;; Let the layout finish sizing its windows first.
      (run-at-time 1 nil
                   (lambda ()
                     (when (buffer-live-p buf)
                       (with-current-buffer buf
                         (ignore-errors (kitty-graphics-browser-fit)))))))
     ((< tries 120)
      (run-at-time 0.5 nil #'my/kitty--fit-when-ready since (1+ tries))))))

(defun my/kitty--fit-after-init (orig &rest args)
  "Run ORIG, a Noteworthy init, with ARGS; then fit the preview it opens.
The browse count is taken before ORIG runs, so a browser it opens at
once counts as new as well as one it opens later."
  (let ((since my/kitty--browse-count))
    (prog1 (apply orig args)
      (when (my/kitty-preview-p)
        (my/kitty--fit-when-ready since)))))

(advice-add 'noteworthy-init :around #'my/kitty--fit-after-init)
(advice-add 'noteworthy-remote-init :around #'my/kitty--fit-after-init)
