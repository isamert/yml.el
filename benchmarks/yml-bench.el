;;; yml-bench.el --- Compare YAML parsers -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright (C) 2026 Isa Mert Gurbuz

;;; Commentary:

;; Build yml-core, then run:
;;
;; emacs --batch -Q -L . -l benchmarks/yml-bench.el \
;;   --eval '(yml-bench-run 1)'
;;
;; Inputs and dependency repositories are cached in separate temporary folders.
;; Setup clones yaml.el and emacs-libyaml, and builds the latter if needed.
;; yaml.el is available but disabled in the default timed comparison.

;; This file is mostly generated with AI.  I selected these YAML files
;; to benchmark specifically because I was dealing with them in
;; swagg.el.

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'url)
(require 'url-http)

(declare-function yml-parse-string "yml" (string &rest arguments))
(declare-function yaml-parse-string "yaml" (string &rest arguments))
(declare-function yaml-read-from-string "libyaml" (string))
(defvar url-http-response-status)

(defvar yml-bench-directory
  (expand-file-name "yml-bench/" temporary-file-directory)
  "Directory in which downloaded benchmark inputs are cached.
Delete a cached file to fetch a fresh copy on the next run.")

(defvar yml-bench-dependency-directory
  (expand-file-name "yml-bench-deps/" temporary-file-directory)
  "Directory for cached yaml.el and emacs-libyaml Git repositories.
Existing clones are reused without fetching updates.")

(defvar yml-bench-libyaml-make-arguments
  '("CC=cc" "LD=cc" "CPPFLAGS=")
  "Arguments passed to make when building emacs-libyaml.
The default uses installed emacs-module.h and yaml.h headers rather than
upstream's relative Emacs source-tree path.  Set CPPFLAGS and LDFLAGS here
if headers or the system libyaml library need nonstandard search paths.")

(defvar yml-bench-inputs
  '(("docker.yaml" . "https://docs.docker.com/reference/api/engine/version/v1.54.yaml")
    ("github.yaml" . "https://raw.githubusercontent.com/github/rest-api-description/refs/heads/main/descriptions/api.github.com/api.github.com.yaml")
    ("gitlab.yaml" . "https://gitlab.com/gitlab-org/gitlab/-/raw/master/doc/api/openapi/openapi_v2.yaml"))
  "Alist of cache filenames and their download URLs.")

(defun yml-bench--yaml-parse-string (string)
  "Parse STRING with yaml.el using representations matching yml.el."
  (yaml-parse-string string :object-type 'hash-table :object-key-type 'string
                     :sequence-type 'array :null-object :null :false-object :false))

(defun yml-bench--yml-parse-string (string)
  "Parse STRING with yml.el using alists."
  (yml-parse-string string :object-type 'alist))

(defun yml-bench--yml-parse-plist (string)
  "Parse STRING with yml.el using plists."
  (yml-parse-string string :object-type 'plist))

(defun yml-bench--libyaml-parse-string (string)
  "Parse API specification STRING with libyaml.
libyaml can return nil on a parse error instead of signaling.  These
benchmark inputs must produce mappings, so reject other root values."
  (let ((result (yaml-read-from-string string)))
    (unless (hash-table-p result)
      (error "libyaml did not return the expected API mapping"))
    result))

(defvar yml-bench-parsers
  '(("yml/hash" yml yml-parse-string)
    ("yml/alist" yml yml-bench--yml-parse-string)
    ("yml/plist" yml yml-bench--yml-parse-plist)
    ("libyaml" libyaml yml-bench--libyaml-parse-string))
  "Parsers to benchmark, as (LABEL FEATURE FUNCTION) entries.
FEATURE is required before timing, or may be nil.  FUNCTION accepts a
YAML string.  Add an adapter function when a library needs specific options.")

(defun yml-bench--command (program &rest arguments)
  "Run PROGRAM with ARGUMENTS, reporting its output on failure."
  (message "Running %s %s..." program (mapconcat #'identity arguments " "))
  (with-temp-buffer
    (let ((status (apply #'call-process program nil t t arguments)))
      (unless (eq status 0)
        (error "%s failed (%s): %s" program status (buffer-string))))))

(defun yml-bench--clone (name url)
  "Return cached repository NAME, cloning URL only when absent."
  (make-directory yml-bench-dependency-directory t)
  (let ((directory (expand-file-name name yml-bench-dependency-directory)))
    (unless (file-directory-p (expand-file-name ".git" directory))
      (when (file-exists-p directory)
        (error "Not a Git clone; move or remove %s" directory))
      (let ((temporary (make-temp-file (concat directory ".clone-") t)))
        (unwind-protect
            (progn
              (yml-bench--command "git" "clone" "--depth" "1" url temporary)
              (rename-file temporary directory))
          (when (file-directory-p temporary)
            (delete-directory temporary t)))))
    directory))

(defun yml-bench--setup-dependencies ()
  "Cache both comparison libraries and build libyaml if needed.
Add successful repositories to load-path.  Return an alist of feature
names and setup errors, so one unavailable library does not stop others.
No system packages are installed; libyaml needs make, a C compiler,
emacs-module.h, and the system libyaml development headers and library."
  (let (errors)
    (dolist (dependency '((yaml "yaml.el" "https://github.com/zkry/yaml.el.git")
                          (libyaml "emacs-libyaml" "https://github.com/syohex/emacs-libyaml.git")))
      (pcase-let ((`(,feature ,name ,url) dependency))
        (condition-case err
            (let* ((directory (yml-bench--clone name url))
                   (default-directory (file-name-as-directory directory)))
              ;; yaml.el is pure Elisp and needs no build.  The upstream
              ;; emacs-libyaml Makefile always produces libyaml-core.so.
              (when (and (eq feature 'libyaml)
                         (not (file-exists-p "libyaml-core.so")))
                (apply #'yml-bench--command "make"
                       yml-bench-libyaml-make-arguments))
              (add-to-list 'load-path directory))
          (error (push (cons feature (error-message-string err)) errors)))))
    errors))

(defun yml-bench--download (filename url)
  "Return cached FILENAME, downloading URL if it is absent.
Only successful, complete HTTP responses are saved to the cache."
  (make-directory yml-bench-directory t)
  (let ((file (expand-file-name filename yml-bench-directory)))
    (unless (file-exists-p file)
      (message "Downloading %s..." url)
      (let ((response (url-retrieve-synchronously url t t 120))
            temporary)
        (unless response
          (error "Download failed or timed out: %s" url))
        (unwind-protect
            (with-current-buffer response
              (unless (and (integerp url-http-response-status)
                           (<= 200 url-http-response-status)
                           (< url-http-response-status 300))
                (error "HTTP %s: %s" url-http-response-status url))
              (goto-char (point-min))
              (unless (re-search-forward "\r?\n\r?\n" nil t)
                (error "Missing HTTP headers: %s" url))
              (when (= (point) (point-max))
                (error "Empty download: %s" url))
              ;; Write beside the destination, then rename atomically.  Failed
              ;; downloads must not become cache hits on subsequent runs.
              (setq temporary (make-temp-file (concat file ".part-")))
              (let ((coding-system-for-write 'no-conversion))
                (write-region (point) (point-max) temporary nil 'silent))
              (rename-file temporary file t))
          (when (and temporary (file-exists-p temporary))
            (delete-file temporary))
          (kill-buffer response))))
    file))

(defun yml-bench-run (&optional repetitions)
  "Benchmark each configured parser on every cached YAML input.
REPETITIONS defaults to 1, since the inputs are large.  Dependency cloning
and builds, downloads, file reads, library loading, and the initial garbage
collection are not timed.  yaml.el is cached but not timed by default.
Report total seconds, seconds per parse, GC count, and GC seconds; parser
or download errors are reported without stopping the remaining cases.
Results go to stdout in batch mode, or to *yml benchmarks* interactively.
Return a list of (FILENAME LABEL RESULT) entries, where RESULT is the
`benchmark-run' result or an error message."
  (interactive "p")
  (setq repetitions (or repetitions 1))
  (unless (and (integerp repetitions) (> repetitions 0))
    (user-error "Repetitions must be a positive integer"))
  (let* ((output (unless noninteractive (get-buffer-create "*yml benchmarks*")))
         (standard-output (or output t))
         (setup-errors (yml-bench--setup-dependencies))
         results)
    (when output
      (with-current-buffer output (erase-buffer))
      (display-buffer output))
    (princ (format "Emacs %s (%s)\nCache: %s\nRepetitions: %d\n\n"
                   emacs-version system-configuration
                   yml-bench-directory repetitions))
    (princ (format "%-14s %-12s %12s %12s %8s %12s\n"
                   "Input" "Parser" "Total (s)" "s/parse" "GCs" "GC (s)"))
    (dolist (input yml-bench-inputs)
      (condition-case err
          (let* ((file (yml-bench--download (car input) (cdr input)))
                 (text (with-temp-buffer
                         (let ((coding-system-for-read 'utf-8-unix))
                           (insert-file-contents file))
                         (buffer-string))))
            (princ (format "\n%s (%d bytes)\n"
                           (car input) (file-attribute-size (file-attributes file))))
            (dolist (parser yml-bench-parsers)
              (pcase-let ((`(,label ,feature ,function) parser))
                (condition-case err
                    (progn
                      (let ((setup-error (assq feature setup-errors)))
                        (when setup-error
                          (error "Dependency setup: %s" (cdr setup-error))))
                      (when feature (require feature))
                      (message "Benchmarking %s with %s..." (car input) label)
                      (garbage-collect)
                      (let ((result (benchmark-run repetitions
                                                   (funcall function text))))
                        (push (list (car input) label result) results)
                        (princ (format "%-14s %-12s %12.6f %12.6f %8d %12.6f\n"
                                       (car input) label (nth 0 result)
                                       (/ (nth 0 result) repetitions)
                                       (nth 1 result) (nth 2 result)))))
                  (error
                   (let ((detail (error-message-string err)))
                     (push (list (car input) label detail) results)
                     (princ (format "%-14s %-12s ERROR: %s\n"
                                    (car input) label detail))))))))
        (error (princ (format "\n%s: ERROR: %s\n"
                              (car input) (error-message-string err))))))
    (nreverse results)))

(provide 'yml-bench)
;;; yml-bench.el ends here
