;;; Commentary:
;;
;; GNU Guix development package.  To build and install, run:
;;
;;   guix package -f guix.scm
;;
;; To use as the basis for a development environment, run:
;;
;;   guix environment -l guix.scm
;;
;;; Code:

(use-modules (ice-9 match)
             (ice-9 popen)
             (ice-9 rdelim)
             (srfi srfi-1)
             (srfi srfi-26)
             ((guix build utils) #:select (with-directory-excursion))
             (guix gexp)
             (guix packages)
             (guix licenses)
             (guix git-download)
             (guix build-system asdf)
             (guix build-system glib-or-gtk)
             (guix build-system trivial)
             (gnu packages)
             (gnu packages lisp)
             (gnu packages gnome)
             (gnu packages gstreamer)
             (gnu packages gtk)
             (gnu packages pkg-config)
             (gnu packages webkit))

(define %source-dir (dirname (current-filename)))

(define git-file?
  (let* ((pipe (with-directory-excursion %source-dir
                 (open-pipe* OPEN_READ "git" "ls-files")))
         (files (let loop ((lines '()))
                  (match (read-line pipe)
                    ((? eof-object?)
                     (reverse lines))
                    (line
                     (loop (cons line lines))))))
         (status (close-pipe pipe)))
    (lambda (file stat)
      (match (stat:type stat)
        ('directory #t)
        ((or 'regular 'symlink)
         (any (cut string-suffix? <> file) files))
        (_ #f)))))

(define-public next-gtk-webkit
  (package
    (name "next-gtk-webkit")
    (version (string-append "1.0.0" "-" "master"))
    (source (local-file %source-dir #:recursive? #t #:select? git-file?))
    (build-system glib-or-gtk-build-system)
    (arguments
     `(#:tests? #f                      ; no tests
       #:make-flags (list "gtk-webkit"
                          "CC=gcc"
                          (string-append "PREFIX=" %output))
       #:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (replace 'install
           (lambda* (#:key (make-flags '()) #:allow-other-keys)
             (apply invoke "make" "install-gtk-webkit" make-flags))))))
    (inputs
     `(("glib-networking" ,glib-networking)
       ("gsettings-desktop-schemas" ,gsettings-desktop-schemas)
       ("webkitgtk" ,webkitgtk)))
    (native-inputs
     `(("pkg-config" ,pkg-config)))
    (home-page "https://next.atlas.engineer")
    (synopsis "Infinitely extensible web-browser (user interface only)")
    (description "Next is a keyboard-oriented, extensible web-browser
inspired by Emacs and designed for power users.  The application has familiar
key-bindings, is fully configurable and extensible in Lisp, and has powerful
features for productive professionals.")
    (license bsd-3)))

(define-public sbcl-next
  (package
    (inherit next-gtk-webkit)
    (name "sbcl-next")
    (build-system asdf-build-system/sbcl)
    (outputs '("out" "lib"))
    (arguments
     `(#:tests? #f                      ; no tests
       #:phases (modify-phases %standard-phases
                  (add-after 'unpack 'patch-platform-port-path
                    (lambda* (#:key inputs #:allow-other-keys)
                      (substitute* "source/ports/gtk-webkit.lisp"
                        (("\"next-gtk-webkit\"")
                         (string-append "\"" (assoc-ref inputs "next-gtk-webkit")
                                        "/bin/next-gtk-webkit\"")))))
                  (add-before 'cleanup 'move-bundle
                    (lambda* (#:key outputs #:allow-other-keys)
                      (define lib (assoc-ref outputs "lib"))
                      (define actual-fasl (string-append
                                           lib
                                           "/lib/sbcl/next.fasl"))
                      (define expected-fasl (string-append
                                             lib
                                             "/lib/sbcl/next--system.fasl"))
                      (pk actual-fasl)
                      (pk expected-fasl)
                      (copy-file actual-fasl expected-fasl)
                      #t))
                  (add-after 'create-symlinks 'build-program
                    (lambda* (#:key outputs #:allow-other-keys)
                      (build-program
                       (string-append (assoc-ref outputs "out") "/bin/next")
                       outputs
                       #:entry-program '((next:start-with-port) 0))))
                  (add-before 'build 'install-assets
                    ;; Since the ASDF build system generates a new .asd with a
                    ;; possibly suffixed and thus illegal version number, assets
                    ;; should not be installed after the 'build phase or else
                    ;; the illegal version will result in NIL in the .desktop
                    ;; file.
                    (lambda* (#:key outputs #:allow-other-keys)
                      (invoke "make" "install-assets"
                              (string-append "PREFIX="
                                             (assoc-ref outputs "out"))))))))
    (inputs
     `(("next-gtk-webkit" ,next-gtk-webkit)
       ;; Lisp libraries:
       ("trivial-features" ,sbcl-trivial-features)
       ("alexandria" ,sbcl-alexandria)
       ("cl-strings" ,sbcl-cl-strings)
       ("cl-string-match" ,sbcl-cl-string-match)
       ("puri" ,sbcl-puri)
       ("queues.simple-queue" ,sbcl-queues.simple-queue)
       ("sqlite" ,sbcl-cl-sqlite)
       ("parenscript" ,sbcl-parenscript)
       ("cl-json" ,sbcl-cl-json)
       ("swank" ,sbcl-slime-swank)
       ("cl-markup" ,sbcl-cl-markup)
       ("cl-css" ,sbcl-cl-css)
       ("usocket" ,sbcl-usocket)
       ("bordeaux-threads" ,sbcl-bordeaux-threads)
       ("s-xml-rpc" ,sbcl-s-xml-rpc)
       ("unix-opts" ,sbcl-unix-opts)))
    (synopsis "Infinitely extensible web-browser (with Lisp development files)")))

(define-public next
  (package
    (inherit next-gtk-webkit)
    (name "next")
    (version (package-version next-gtk-webkit))
    (build-system trivial-build-system)
    (arguments
     `(#:modules
       ((guix build utils))
       #:builder
       (begin
         (use-modules (guix build utils))
         (let ((out (assoc-ref %outputs "out")))
           (copy-recursively (assoc-ref %build-inputs "sbcl-next") out)
           (delete-file-recursively (string-append out "/.asd-files"))
           (delete-file (string-append out "/bin/next-exec.fasl")))
         #t)))
    (native-inputs
     `(("sbcl-next" ,sbcl-next)))
    (inputs
     ;; TODO: Shouldn't sqlite be a dependency?
     `(("next-gtk-webkit" ,next-gtk-webkit)))
    (synopsis "Infinitely extensible web-browser")))

next
