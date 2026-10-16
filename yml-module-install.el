;;; yml-module-install.el --- Provision the yml native module -*- lexical-binding: t; -*-

;; Copyright (C) 2026 by Isa Mert Gurbuz

;; Author: Isa Mert Gurbuz <isamertgurbuz@gmail.com>
;; URL: https://github.com/isamert/yml.el
;; Version: 0.1.3
;; License: GPL-3.0-or-later
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Download and install the yml module automatically; either by
;; downloading pre compiled module files or by compiling with Cargo.
;;
;; You can direct users to do M-x `yml-install-module' to
;; automatically install the module.  This asks user for if they want
;; to download or build the library and does the rest automatically.
;; Users can also use the following commands directly:
;;
;; - `yml-download-module'
;; - `yml-build-module'

;;; Code:

(defvar url-http-end-of-headers)
(defvar url-http-response-status)
(defvar compilation-start-hook)

(defgroup yml nil "YAML parsing and serialization." :group 'data)

(defconst yml--repository-url "https://github.com/isamert/yml.el")

(defconst yml--module-name "yml-core")

(defconst yml--build-buffer-name "*yml-build*")

(defconst yml--checksum-manifest "SHA256SUMS")

(defconst yml--module-version "0.1.3"
  "Release matching this version of the Lisp library.")

(defcustom yml-module-directory (expand-file-name "yml/" user-emacs-directory)
  "Directory for installed native modules, outside the package tree.
Modules are stored in version- and platform-specific subdirectories.
Automatically loaded on any yml- function call using
`yml--ensure-module'."
  :type 'directory :group 'yml)

(defconst yml--module-api-version 1
  "Required native API version, independent of the package release.
Bump together with Rust's API version for incompatible interface
changes.")

(declare-function yml-core--api-version "yml-core" ())

(define-error 'yml-module-unavailable "yml native module unavailable")
(define-error 'yml-module-incompatible "yml native module incompatible")

(defun yml--source-directory ()
  "Return the validated package source directory, following symlinks."
  (let* ((library (or (locate-library "yml-module-install.el" t)
                      (user-error "Cannot locate the yml source tree")))
         (directory (file-name-directory (file-truename library))))
    (unless (file-readable-p (expand-file-name "Cargo.toml" directory))
      (user-error "Missing Cargo.toml in %s; install yml with its Rust sources"
                  directory))
    directory))

(defun yml--check-module-api ()
  "Refuse calls into a native module with an incompatible API."
  (let ((actual (and (fboundp 'yml-core--api-version)
                     (yml-core--api-version))))
    (unless (equal actual yml--module-api-version)
      (signal 'yml-module-incompatible
              (list (format
                     "Loaded yml module API is %s; Lisp requires %s. Run M-x yml-build-module to build matching sources (or M-x yml-install-module to reinstall), then restart Emacs"
                     (or actual "unknown") yml--module-api-version))))))

(defun yml--installed-module ()
  (expand-file-name
   (concat yml--module-name (or module-file-suffix ".so"))
   (expand-file-name (concat yml--module-version "/" system-configuration "/")
                     yml-module-directory)))

(defun yml--check-module-support ()
  (unless (and module-file-suffix (fboundp 'module-load))
    (user-error "This Emacs was built without dynamic module support")))

(defvar yml--checked-module-api-version nil)

(defsubst yml--ensure-module ()
  (unless (featurep 'yml-core)
    (setq yml--checked-module-api-version nil)
    (yml--load-module))
  (unless (equal yml--checked-module-api-version yml--module-api-version)
    (yml--check-module-api)
    (setq yml--checked-module-api-version yml--module-api-version)))

(defun yml--load-module ()
  (condition-case err
      (progn
        (yml--check-module-support)
        (let ((installed (yml--installed-module)))
          (if (file-exists-p installed)
              (module-load installed)
            (require 'yml-core)))
        (unless (featurep 'yml-core)
          (error "Module did not provide yml-core")))
    (error
     (signal 'yml-module-unavailable
             (list (format "yml native module is unavailable for %s. Run M-x yml-install-module. Details: %s"
                           system-configuration (error-message-string err)))))))

(defun yml--architecture (configuration)
  (pcase (car (split-string configuration "-"))
    ("amd64" "x86_64")
    ("arm64" "aarch64")
    (arch arch)))

(defun yml--release-target ()
  "Return a supported release target, or signal an error.
GNU/Linux assets require glibc; musl and Android are not supported."
  (let* ((arch (yml--architecture system-configuration))
         (os (pcase system-type
               ('darwin "apple-darwin")
               ('windows-nt (when (equal arch "x86_64") "pc-windows-msvc"))
               ('gnu/linux
                (when (and (string-match-p "linux-gnu" system-configuration)
                           (not (string-match-p "musl\\|android" system-configuration))
                           (not (and (executable-find "ldd")
                                     (with-temp-buffer
                                       (call-process "ldd" nil t nil "--version")
                                       (string-match-p "musl" (buffer-string))))))
                  "unknown-linux-gnu")))))
    (unless (and (member arch '("x86_64" "aarch64")) os)
      (user-error "No prebuilt yml module for %s; use M-x yml-build-module"
                  system-configuration))
    (concat arch "-" os)))

(defun yml--download-file (url destination)
  (require 'url)
  (require 'url-http)
  (unless (string-prefix-p "https://" url)
    (error "Refusing non-HTTPS URL: %s" url))
  (let ((buffer (url-retrieve-synchronously url t t 60)))
    (unless buffer (error "Download failed: %s" url))
    (unwind-protect
        (with-current-buffer buffer
          (unless (and (boundp 'url-http-response-status)
                       (eq url-http-response-status 200)
                       url-http-end-of-headers)
            (error "Download failed (HTTP %s): %s" url-http-response-status url))
          (let ((coding-system-for-write 'no-conversion))
            (write-region (1+ url-http-end-of-headers) (point-max)
                          destination nil 'silent)))
      (kill-buffer buffer))))

(defun yml--verify-checksum (file manifest asset)
  (let ((expected
         (with-temp-buffer
           (insert-file-contents manifest)
           (goto-char (point-min))
           (when (re-search-forward
                  (concat "^\\([[:xdigit:]]\\{64\\}\\) [ *]"
                          (regexp-quote asset) "$") nil t)
             (downcase (match-string 1))))))
    (unless expected (error "No checksum for %s" asset))
    (unless (equal expected
                   (with-temp-buffer
                     (set-buffer-multibyte nil)
                     (insert-file-contents-literally file)
                     (secure-hash 'sha256 (current-buffer))))
      (error "Checksum mismatch for %s" asset))))

(defun yml--install-module-file (staged destination)
  (rename-file staged destination t)
  (if (featurep 'yml-core)
      (message "yml module installed. Restart Emacs to use the new module")
    (yml--ensure-module)
    (message "yml module installed and loaded")))

;;;###autoload
(defun yml-download-module ()
  "Download and verify the prebuilt module for this package release.
If a module is already loaded, restart Emacs to use the replacement."
  (interactive)
  (yml--check-module-support)
  (let* ((target (yml--release-target))
         (asset (concat yml--module-name "-" target module-file-suffix))
         (base (format "%s/releases/download/v%s/"
                       yml--repository-url yml--module-version))
         (destination (yml--installed-module))
         staging manifest)
    (make-directory (file-name-directory destination) t)
    (unwind-protect
        (progn
          (setq staging (make-temp-file (concat destination ".tmp."))
                manifest (make-temp-file (concat destination ".checksums.")))
          (message "Downloading yml module for %s..." target)
          (yml--download-file (concat base asset) staging)
          (yml--download-file (concat base yml--checksum-manifest) manifest)
          (yml--verify-checksum staging manifest asset)
          (yml--install-module-file staging destination))
      (dolist (file (list staging manifest))
        (when (and file (file-exists-p file)) (delete-file file))))))

(defun yml--build-target ()
  (let ((target
         (with-temp-buffer
           (unless (eq 0 (call-process "rustc" nil t nil "-vV"))
             (error "Could not determine Rust's host target"))
           (goto-char (point-min))
           (unless (re-search-forward "^host: \\(.*\\)$" nil t)
             (error "rustc did not report a host target"))
           (match-string 1))))
    (unless (equal (yml--architecture target)
                   (yml--architecture system-configuration))
      (user-error "Rust target %s does not match this Emacs (%s)"
                  target system-configuration))
    target))

(defun yml--finish-build (success built destination)
  "Install BUILT on SUCCESS."
  (condition-case err
      (if (not success)
          (message "yml build failed or cancelled; see %s" yml--build-buffer-name)
        (make-directory (file-name-directory destination) t)
        (let ((staged (make-temp-file (concat destination ".tmp."))))
          (unwind-protect
              (progn
                (copy-file built staged t)
                (yml--install-module-file staged destination))
            (when (file-exists-p staged) (delete-file staged)))))
    (error (display-warning 'yml (error-message-string err)))))

(defun yml--watch-build (process built destination)
  (let ((sentinel (process-sentinel process))
        (finished nil))
    (set-process-sentinel
     process
     (lambda (proc status)
       (if (or finished (not (memq (process-status proc) '(exit signal))))
           (funcall sentinel proc status)
         (setq finished t)
         (let ((success (and (eq (process-status proc) 'exit)
                             (zerop (process-exit-status proc))
                             (buffer-live-p (process-buffer proc)))))
           (unwind-protect
               (funcall sentinel proc status)
             (yml--finish-build success built destination))))))))

;;;###autoload
(defun yml-build-module ()
  "Asynchronously build the local yml sources with Cargo and install them.
If a module is loaded, restart Emacs after building."
  (interactive)
  (yml--check-module-support)
  (require 'compile)
  (dolist (program '("cargo" "rustc"))
    (unless (executable-find program) (user-error "%s is required" program)))
  (when (and (get-buffer yml--build-buffer-name)
             (get-buffer-process yml--build-buffer-name))
    (user-error "A yml build is already running"))
  (let* ((default-directory (yml--source-directory))
         (target (yml--build-target))
         (target-dir (expand-file-name "target" default-directory))
         (destination (yml--installed-module))
         (library (pcase system-type
                    ('darwin "libyml.dylib")
                    ('windows-nt "yml.dll")
                    (_ "libyml.so")))
         (built (expand-file-name (concat target "/release/" library) target-dir))
         (started nil)
         (compilation-start-hook
          (cons (lambda (process)
                  (unless started
                    (setq started t)
                    (yml--watch-build process built destination)))
                compilation-start-hook)))
    (compilation-start
     (concat "cargo build --release --locked --lib --target "
             (shell-quote-argument target) " --target-dir "
             (shell-quote-argument target-dir))
     'compilation-mode (lambda (_) yml--build-buffer-name))))

;;;###autoload
(defun yml-install-module ()
  "Install or reinstall a module by downloading or building locally.
An already loaded module is not replaced in this process; restart Emacs
after installation to use its replacement."
  (interactive)
  (yml--check-module-support)
  (when (featurep 'yml-core)
    (message "A yml module is already loaded. Reinstalling takes effect after restarting Emacs"))
  (pcase (car (read-multiple-choice
               (if (featurep 'yml-core)
                   "Reinstall yml module (restart required)?"
                 "Install yml native module?")
               '((?d "download" "Download a verified prebuilt release")
                 (?b "build" "Build local sources with Cargo")
                 (?c "cancel" "Do not install"))))
    (?d (yml-download-module))
    (?b (yml-build-module))
    (?c (message "yml installation cancelled"))))

(provide 'yml-module-install)

;; Local Variables:
;; package-lint-main-file: "yml.el"
;; End:
;;; yml-module-install.el ends here
