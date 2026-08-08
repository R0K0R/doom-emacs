;; -*- no-byte-compile: t; -*-
;;; app/noteworthy/packages.el

(package! websocket)
(package! dtrt-indent)
;; :pin required for nix-doom-emacs-unstraightened: neither package exists in
;; nixpkgs/emacs-overlay, so without a pin resolution fails outright (noteworthy
;; points at an unpublished private repo and can only ever resolve via :pin).
(package! typst-preview
  :recipe (:type git :host github :repo "havarddj/typst-preview.el")
  :pin "7e89cf105e4fef5e79977a4a790d5b3b18d305f6")

(package! noteworthy
  :recipe (:type git :host github :repo "R0K0R/noteworthy.el")
  :pin "0c9bc64a68a2871b66904034c73a5e81772fd3e4")

;; Real-time collaboration package (local for now)
;;(package! noteworthy-collab
;;  :recipe (:local-repo "~/Typst/noteworthy-collab.el"))

(package! treemacs-nerd-icons)

(package! pdf-view-restore)
