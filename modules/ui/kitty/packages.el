;; -*- no-byte-compile: t; -*-
;;; ui/kitty/packages.el

;; My fork of cashmeredev/kitty-graphics.el, carrying fixes not upstream.
(package! kitty-graphics
  :recipe (:host github :repo "R0K0R/kitty-graphics.el")
  :pin "3470cee5449d2417fb185c3366555e8130d40a66")
