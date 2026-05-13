;; -*- no-byte-compile: t; -*-
;;; app/noteworthy/packages.el

(package! websocket)
(package! dtrt-indent)
(package! typst-preview
  :recipe (:type git :host github :repo "havarddj/typst-preview.el"))

(package! noteworthy
  :recipe (:type git :host github :repo "R0K0R/noteworthy.el"))

;; Real-time collaboration package (local for now)
;;(package! noteworthy-collab
;;  :recipe (:local-repo "~/Typst/noteworthy-collab.el"))

(package! treemacs-nerd-icons)

(package! pdf-view-restore)
