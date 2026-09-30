;;; ui/kitty/init.el -*- lexical-binding: t; -*-

;; What the terminal supports, stated instead of asked.  With the default
;; `check', term/xterm.el asks the terminal for its device attributes when it
;; sets it up, and when an answer does not come at once it stops waiting and
;; lets the command loop decode it on arrival.  Arriving mid-start-up, next to
;; kitty-graphics' own probes, an answer could be split between the two: Emacs
;; started with a stray ESC prefix pending ("ESC-") and the rest of the answer
;; typed as input.  For Kitty the check only ever enables OSC 52 selection --
;; its version answer counts as an old xterm, and its attributes list 52 -- so
;; that is stated here.  Set in init.el because terminal set-up follows the
;; init file but precedes config.el.
(setq xterm-extra-capabilities '(setSelection))
