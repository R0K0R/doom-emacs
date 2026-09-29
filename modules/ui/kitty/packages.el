;; -*- no-byte-compile: t; -*-
;;; ui/kitty/packages.el

;; My fork of cashmeredev/kitty-graphics.el, carrying fixes not upstream.
(package! kitty-graphics
  :recipe (:host github :repo "R0K0R/kitty-graphics.el")
  :pin "47cf31225eafacdc66c2b03cd9ab809a0e7e4219")
