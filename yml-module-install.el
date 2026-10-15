;;; yml-module-install.el --- Provision the yml native module -*- lexical-binding: t; -*-

;; Copyright (C) 2026 by Isa Mert Gurbuz

;; Author: Isa Mert Gurbuz <isamertgurbuz@gmail.com>
;; URL: https://github.com/isamert/yml.el
;; Version: 0.1.2
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

(defconst yml--source-buffer-name "*yml-source*")

(defconst yml--checksum-manifest "SHA256SUMS")

(defconst yml--module-version "0.1.2"
  "Release matching this version of the Lisp library.")

(defcustom yml-module-directory (expand-file-name "yml/" user-emacs-directory)
  "Directory for installed native modules, outside the package tree.
Modules are stored in version- and platform-specific subdirectories.
Automatically loaded on any yml- function call using
`yml--ensure-module'."
  :type 'directory :group 'yml)

(define-error 'yml-module-unavailable "yml native module unavailable")

(defun yml--installed-module ()
  (expand-file-name
   (concat yml--module-name (or module-file-suffix ".so"))
   (expand-file-name (concat yml--module-version "/" system-configuration "/")
                     yml-module-directory)))

(defun yml--check-module-support ()
  (unless (and module-file-suffix (fboundp 'module-load))
    (user-error "This Emacs was built without dynamic module support")))

(defsubst yml--ensure-module ()
  (unless (featurep 'yml-core)
    (yml--load-module)))

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

(defun yml--finish-build (success work built destination)
  "Install BUILT on SUCCESS and clean up WORK in every case."
  (unwind-protect
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
        (error (display-warning 'yml (error-message-string err))))
    (delete-directory work t)))

(defun yml--watch-build (process work built destination)
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
             (yml--finish-build success work built destination))))))))

;;;###autoload
(defun yml-build-module ()
  "Download this release's source and asynchronously build with Cargo.
Build outputs are retained in the *yml-build* compilation buffer."
  (interactive)
  (yml--check-module-support)
  (require 'compile)
  (dolist (program '("cargo" "rustc" "tar"))
    (unless (executable-find program) (user-error "%s is required" program)))
  (when (and (get-buffer yml--build-buffer-name)
             (get-buffer-process yml--build-buffer-name))
    (user-error "A yml build is already running"))
  (let* ((target (yml--build-target))
         (work (make-temp-file "yml-source-" t))
         (archive (expand-file-name "source.tar.gz" work))
         (destination (yml--installed-module))
         (started nil))
    (unwind-protect
        (progn
          (yml--download-file
           (format "%s/archive/refs/tags/v%s.tar.gz"
                   yml--repository-url yml--module-version) archive)
          (unless (eq 0 (call-process "tar" nil yml--source-buffer-name nil
                                      "-xzf" archive "-C" work))
            (error "Source extraction failed; see %s" yml--source-buffer-name))
          (let* ((default-directory
                   (expand-file-name (concat "yml.el-" yml--module-version "/") work))
                 (target-dir (expand-file-name "target" work))
                 (library (pcase system-type
                            ('darwin "libyml.dylib")
                            ('windows-nt "yml.dll")
                            (_ "libyml.so")))
                 (built (expand-file-name (concat target "/release/" library) target-dir))
                 (compilation-start-hook
                  (cons
                   (lambda (process)
                     (unless started
                       (setq started t)
                       (yml--watch-build process work built destination)))
                   compilation-start-hook)))
            (compilation-start
             (concat "cargo build --release --locked --lib --target "
                     (shell-quote-argument target) " --target-dir "
                     (shell-quote-argument target-dir))
             'compilation-mode (lambda (_) yml--build-buffer-name))))
      (unless started (delete-directory work t)))))

;;;###autoload
(defun yml-install-module ()
  "Load an existing module, or ask whether to download or build one."
  (interactive)
  (yml--check-module-support)
  (if (condition-case nil (progn (yml--ensure-module) t)
        (yml-module-unavailable nil))
      (message "yml native module is already loaded")
    (pcase (car (read-multiple-choice
                 "Install yml native module?"
                 '((?d "download" "Download a verified prebuilt release")
                   (?b "build" "Download source and build with Cargo")
                   (?c "cancel" "Do not install"))))
      (?d (yml-download-module))
      (?b (yml-build-module))
      (?c (message "yml installation cancelled")))))

(provide 'yml-module-install)

;; Local Variables:
;; package-lint-main-file: "yml.el"
;; End:
;;; yml-module-install.el ends here
