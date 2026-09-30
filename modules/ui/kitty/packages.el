;; -*- no-byte-compile: t; -*-
;;; ui/kitty/packages.el

;; My fork of cashmeredev/kitty-graphics.el, carrying fixes not upstream.
(package! kitty-graphics
  :recipe (:host github :repo "R0K0R/kitty-graphics.el")
  :pin "1c4d9fed8ccf79ff63c245d1af2ea6d122719afd")
