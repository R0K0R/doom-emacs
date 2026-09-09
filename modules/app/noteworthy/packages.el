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
  :pin "5b3f03c26ae38da3d5c2f014ab6ba91c4415a046")

;; Real-time collaboration package. Fetched from GitHub rather than a
;; :local-repo: a local checkout cannot be resolved deterministically, so
;; nix-doom-emacs-unstraightened refuses it outright --
;;   noteworthy-collab: not in nixpkgs or emacs-overlay, not pinned.
;; Same reason typst-preview and noteworthy above carry pins.
(package! noteworthy-collab
  :recipe (:type git :host github :repo "R0K0R/noteworthy-collab.el")
  :pin "041236f943b79739e03e5db48bbd44666865b504")

(package! treemacs-nerd-icons)

(package! pdf-view-restore)
