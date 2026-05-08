;;; app/codesolve/config.el -*- lexical-binding: t; -*-

;; Course configuration: (NAME . (:code PATH :pdf PATH))
(defvar codesolve-courses
  '(("PPS" (:code "/home/r0k0r/Documents/KSA/PPS/code_student/"
            :pdf "/home/r0k0r/Documents/KSA/PPS/problem_set.pdf"))
    ("DS"  (:code "/home/r0k0r/Documents/KSA/DS/code/"
            :pdf "/home/r0k0r/Documents/KSA/DS/textbook.pdf")))
  "An association list of courses and their associated file paths.")

(defvar codesolve-baekjoon-dir "~/code/baekjoon/"
  "Directory for Baekjoon problem solutions.")

;; Configuration
(defvar codesolve-reference-width 80
  "Width (in columns) of the right reference window. Persisted via savehist.")

;; Persist this variable
(after! savehist
  (add-to-list 'savehist-additional-variables 'codesolve-reference-width))

;; Internal state
(defvar codesolve--current-reference-window nil
  "The window showing the reference (xwidget or PDF).")

(defvar codesolve--current-pdf-buffer nil
  "The PDF buffer for M-HJKL control.")

(defun codesolve--track-width (_frame)
  "Update `codesolve-reference-width` when the reference window is resized."
  (when (and (window-live-p codesolve--current-reference-window)
             (> (window-width codesolve--current-reference-window) 10))
    (setq codesolve-reference-width (window-width codesolve--current-reference-window))))

(add-hook 'window-size-change-functions #'codesolve--track-width)

;;; Layout Functions

(defun codesolve--fetch-baekjoon-title (problem-number)
  "Fetch problem title from acmicpc.net using curl (returns nil on failure)."
  (let ((url (format "https://www.acmicpc.net/problem/%d" problem-number))
        (cmd (format "curl -s -L -H 'User-Agent: Mozilla/5.0' https://www.acmicpc.net/problem/%d" problem-number)))
    (with-temp-buffer
      (when (zerop (call-process-shell-command cmd nil t))
        (goto-char (point-min))
        (when (re-search-forward "<span id=\"problem_title\">\\(.*?\\)</span>" nil t)
          (match-string 1))))))

(defun codesolve--ensure-layout (project-dir main-buffer reference-type reference-arg)
  "Ensure layout exists. Editor -> Ref -> Term -> Treemacs.
Resizes the reference window ONLY after all other windows are created."
  
  ;; 1. Reset to single window (Editor)
  (delete-other-windows)
  (switch-to-buffer main-buffer)
  (setq-local default-directory project-dir)
  
  (let ((main-window (selected-window))
        (ref-buffer nil)) ;; We will capture the reference buffer here
    
    ;; 2. Reference Pane (Right) - Created with Desired Width
    (pcase reference-type
      ('xwidget
       (if (fboundp 'xwidget-webkit-browse-url)
           (progn
             (xwidget-webkit-browse-url reference-arg t)
             (setq ref-buffer (current-buffer))) ;; Capture buffer for later resize
         (message "xwidget not available")))
      
      ('pdf
       ;; PDF manual split
       (let ((ref-window (split-window-right (- codesolve-reference-width))))
         (select-window ref-window)
         (setq codesolve--current-reference-window ref-window)
         (when (and reference-arg (file-exists-p reference-arg))
           (find-file reference-arg)
           (setq codesolve--current-pdf-buffer (current-buffer))
           (setq ref-buffer (current-buffer))))))

    ;; 3. Terminal (Below Main)
    (select-window main-window)
    (let ((term-window (split-window-below (floor (* 0.75 (window-height))))))
      (select-window term-window)
      (when (fboundp 'vterm)
        (let ((vterm-shell "distrobox-host-exec /usr/bin/fish"))
          (let ((buf (vterm--internal (lambda (b) (switch-to-buffer b)))))
             (switch-to-buffer buf)
             (vterm-send-string (format "cd %s\n" (shell-quote-argument project-dir)))))))

    ;; 4. Treemacs (Left side)
    (select-window main-window)
    (when (fboundp 'treemacs)
      (let ((default-directory project-dir))
        (treemacs-select-window) 
        (treemacs)
        (treemacs-add-and-display-current-project-exclusively)))
    ;; (treemacs-project-follow-mode 1)
    
    ;; 5. FINAL RESIZE & PERSISTENCE
    (when (and ref-buffer (get-buffer-window ref-buffer))
      (let ((win (get-buffer-window ref-buffer)))
        (select-window win)
        (setq codesolve--current-reference-window win)
        
        ;; Force resize if needed (though split-window-right usually handles it)
        (let ((delta (- codesolve-reference-width (window-width))))
          (unless (zerop delta)
            (window-resize nil delta t)))
        
        ;; Lock the width so future automated splits don't mess it up
        (window-preserve-size win t t)))

    ;; Final focus on main
    (select-window main-window))
      
  (when (fboundp 'my/sync-font-columns)
    (my/sync-font-columns (selected-frame))))

;;; Commands

;;;###autoload
(defun codesolve-baekjoon (problem-number)
  "Start Baekjoon workspace for PROBLEM-NUMBER.
Auto-generates [NUMBER].py and fetches problem title."
  (interactive "nProblem number: ")
  (let* ((project-dir (expand-file-name codesolve-baekjoon-dir))
         (filename (format "%d.py" problem-number))
         (filepath (expand-file-name filename project-dir))
         (url (format "https://www.acmicpc.net/problem/%d" problem-number)))
    
    ;; Create dir/file if needed
    (unless (file-directory-p project-dir)
      (make-directory project-dir t))
    
    (let ((buffer (find-file-noselect filepath)))
      (with-current-buffer buffer
        (when (= (buffer-size) 0)
          (let ((title (or (codesolve--fetch-baekjoon-title problem-number) "Unknown Problem")))
            (insert (format "\"\"\"\n%d: %s\nLink: %s\n\"\"\"\nimport sys\n\ndef solve():\n    pass\n\nif __name__ == '__main__':\n    solve()\n" 
                            problem-number title url))
            (save-buffer))))
      
      (codesolve--ensure-layout project-dir buffer 'xwidget url)
      (message "Baekjoon #%d loaded" problem-number))))

;;;###autoload
(defun codesolve-homework ()
  "Start homework workspace. Prompts for course selection."
  (interactive)
  (let* ((course-names (mapcar #'car codesolve-courses))
         (choice (completing-read "Course: " course-names nil t))
         ;; Use cadr here to get the actual plist inside the list
         (config (cadr (assoc choice codesolve-courses)))
         (code-path (plist-get config :code))
         (pdf-path (plist-get config :pdf)))

    ;; Ensure dir exists
    (unless (and code-path (file-directory-p code-path))
      (make-directory code-path t))

    (let ((buffer (find-file-noselect (expand-file-name "scratch.py" code-path))))
      (codesolve--ensure-layout code-path buffer 'pdf pdf-path)
      (message "Homework: %s loaded" choice))))

;;; PDF Control (reuse M-HJKL pattern)

(defun codesolve-pdf-scroll-up ()
  "Scroll PDF up."
  (interactive)
  (when (and codesolve--current-pdf-buffer
             (buffer-live-p codesolve--current-pdf-buffer))
    (with-selected-window (get-buffer-window codesolve--current-pdf-buffer)
      (pdf-view-scroll-down-or-previous-page))))

(defun codesolve-pdf-scroll-down ()
  "Scroll PDF down."
  (interactive)
  (when (and codesolve--current-pdf-buffer
             (buffer-live-p codesolve--current-pdf-buffer))
    (with-selected-window (get-buffer-window codesolve--current-pdf-buffer)
      (pdf-view-scroll-up-or-next-page))))

(defun codesolve-pdf-scroll-left ()
  "Scroll PDF left."
  (interactive)
  (when (and codesolve--current-pdf-buffer
             (buffer-live-p codesolve--current-pdf-buffer))
    (with-selected-window (get-buffer-window codesolve--current-pdf-buffer)
      (image-scroll-right 50))))

(defun codesolve-pdf-scroll-right ()
  "Scroll PDF right."
  (interactive)
  (when (and codesolve--current-pdf-buffer
             (buffer-live-p codesolve--current-pdf-buffer))
    (with-selected-window (get-buffer-window codesolve--current-pdf-buffer)
      (image-scroll-left 50))))

;;; Keybindings (global M-HJKL for PDF control)
(map! :n "M-H" #'codesolve-pdf-scroll-left
      :n "M-J" #'codesolve-pdf-scroll-down
      :n "M-K" #'codesolve-pdf-scroll-up
      :n "M-L" #'codesolve-pdf-scroll-right)

(provide 'codesolve)


