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
  ;; :files must be spelled out: straight's default directive copies only
  ;; Lisp and info files, which would leave the shipped snippets/ behind.
  :recipe (:type git :host github :repo "R0K0R/noteworthy.el"
           :files (:defaults "snippets"))
  :pin "29511032ba20392b4d65a2b0b6ecca31c2810dd1")

;; Real-time collaboration package. Fetched from GitHub rather than a
;; :local-repo: a local checkout cannot be resolved deterministically, so
;; nix-doom-emacs-unstraightened refuses it outright --
;;   noteworthy-collab: not in nixpkgs or emacs-overlay, not pinned.
;; Same reason typst-preview and noteworthy above carry pins.
(package! noteworthy-collab
  :recipe (:type git :host github :repo "R0K0R/noteworthy-collab.el")
  :pin "c9302ffda520935a7b735fbb756e5db4e27809e6")

(package! treemacs-nerd-icons)

(package! pdf-view-restore)
