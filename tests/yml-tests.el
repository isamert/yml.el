;;; yml-tests.el --- Native YAML integration tests -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Copyright (C) 2026 Isa Mert Gurbuz

;;; Commentary:

;; Test the public wrappers, Lisp/native conversions, and representative
;; YAML documents parsed and serialized through the native module.
;;   emacs --batch -Q -L . -l tests/yml-tests.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yml)
(require 'yml-core)
(yml--ensure-module)

(defun yml-tests--field (object key object-type)
  "Read string KEY from OBJECT represented by OBJECT-TYPE."
  (cl-ecase object-type
    (hash-table (gethash key object))
    (alist (cdr (assq (intern key) object)))
    (plist (plist-get object (intern (concat ":" key))))))

(ert-deftest yml-wrapper-argument-forwarding ()
   (cl-letf (((symbol-function 'yml-core--parse-string) #'list)
             ((symbol-function 'yml-core--serialize) #'list))
     (should (equal (yml-parse-string "input")
                    '("input" hash-table string array :null :false nil)))
     (should (equal (yml-parse-string-all "input")
                    '("input" hash-table string array :null :false parse-all)))
     (dolist (parser '(yml-parse-string yml-parse-string-all))
       (dolist (case '((hash-table . string) (alist . symbol) (plist . keyword)))
         (should (eq (nth 2 (funcall parser "input" :object-type (car case)))
                     (cdr case)))))
     (should (equal (yml-serialize [1]) '([1] :null :false)))
     (dolist (parser '(yml-parse-string yml-parse-string-all))
       (should (equal (funcall parser "input"
                               :false-object 'no :null-object nil
                               :array-type 'list :object-type 'plist
                               :object-key-type 'keyword)
                      (list "input" 'plist 'keyword 'list nil 'no
                            (when (eq parser 'yml-parse-string-all)
                              'parse-all)))))
     (should (equal (yml-serialize [1] :false-object nil :null-object 'none)
                    '([1] none nil)))))

(ert-deftest yml-native-parser-representations ()
  (let ((yaml "outer: {items: [1, {name: café}], empty: [], mapping: {}}"))
    (dolist (object-type '(hash-table alist plist))
      (dolist (array-type '(array list))
        (dolist (parser '(yml-parse-string yml-parse-string-all))
          (ert-info ((format "%s / %s / %s" parser object-type array-type))
            (let* ((parsed (funcall parser yaml :object-type object-type
                                    :array-type array-type))
                   (root (if (eq parser 'yml-parse-string-all)
                             (progn (should (= (length parsed) 1)) (car parsed))
                           parsed))
                   (outer (yml-tests--field root "outer" object-type))
                   (items (yml-tests--field outer "items" object-type))
                   (empty (yml-tests--field outer "empty" object-type))
                   (mapping (yml-tests--field outer "mapping" object-type)))
              (should (if (eq array-type 'array)
                          (vectorp items) (listp items)))
              (should (= (length items) 2))
              (should (= (elt items 0) 1))
              (should (equal (yml-tests--field (elt items 1) "name" object-type)
                             "café"))
              (should (equal empty (if (eq array-type 'array) [] nil)))
              (if (eq object-type 'hash-table)
                  (progn
                    (should (hash-table-p root))
                    (should (eq (hash-table-test root) 'equal))
                    (should (hash-table-p mapping))
                    (should (= (hash-table-count mapping) 0)))
                (should (null mapping))))))))
    (should (equal (yml-parse-string "name: café" :object-type 'alist)
                   '((name . "café"))))
    (should (equal (yml-parse-string "name: café" :object-type 'plist)
                   '(:name "café")))
    (should (= (gethash 7 (yml-parse-string "7: 8")) 8))
    (should (equal (yml-parse-string "7: 8" :object-type 'alist
                                     :object-key-type 'string) '((7 . 8))))
    (should (= (gethash "key" (yml-parse-string "{key: 1, key: 2}")) 2))
    (should (equal (yml-parse-string "{key: 1, key: 2}" :object-type 'alist)
                   '((key . 1) (key . 2))))
    (should (equal (yml-parse-string "{key: 1, key: 2}" :object-type 'plist)
                   '(:key 1 :key 2)))
    (dolist (object-type '(hash-table alist plist))
      (let* ((root (yml-parse-string "source: &node {items: [1, 2]}\ncopy: *node"
                                     :object-type object-type))
             (copy (yml-tests--field root "copy" object-type)))
        (should (equal (yml-tests--field copy "items" object-type) [1 2]))))
    (should (equal (yml-parse-string "[!!int 42, !!str 42, !!float 1, 'false']")
                   [42 "42" 1.0 "false"]))))

(ert-deftest yml-native-object-key-types ()
  (dolist (parser '(yml-parse-string yml-parse-string-all))
    (dolist (object-type '(hash-table alist plist))
      (dolist (key-type '(symbol keyword string))
        (ert-info ((format "%s / %s / %s" parser object-type key-type))
          (let* ((parsed (funcall parser "outer: {name: café}"
                                  :object-type object-type
                                  :object-key-type key-type))
                 (root (if (eq parser 'yml-parse-string-all) (car parsed) parsed))
                 (key (cond ((eq key-type 'string) "outer")
                            ((or (eq object-type 'plist)
                                 (eq key-type 'keyword)) :outer)
                            (t 'outer)))
                 (name (cond ((stringp key) "name")
                             ((keywordp key) :name)
                             (t 'name)))
                 (child (cl-ecase object-type
                          (hash-table (gethash key root))
                          (alist (cdr (assoc key root)))
                          (plist (lax-plist-get root key)))))
            (should (equal (cl-ecase object-type
                             (hash-table (gethash name child))
                             (alist (cdr (assoc name child)))
                             (plist (lax-plist-get child name)))
                           "café")))
          (if (eq key-type 'string)
              (let* ((parsed (funcall parser "7: 8" :object-type object-type
                                      :object-key-type key-type))
                     (root (if (eq parser 'yml-parse-string-all)
                               (car parsed) parsed)))
                (should (equal (cl-ecase object-type
                                 (hash-table (gethash 7 root))
                                 (alist (cdr (assq 7 root)))
                                 (plist (plist-get root 7)))
                               8)))
            (should-error (funcall parser "7: 8" :object-type object-type
                                   :object-key-type key-type)
                          :type 'yml-non-string-key)))))
    (should-error (funcall parser "name: value" :object-key-type 'invalid)
                  :type 'error)))

(ert-deftest yml-native-hash-table-key-serialization ()
  (dolist (parser '(yml-parse-string yml-parse-string-all))
    (dolist (key-type '(symbol keyword))
      (let* ((parsed (funcall parser "outer: {name: café}"
                              :object-key-type key-type))
             (root (if (eq parser 'yml-parse-string-all) (car parsed) parsed))
             (serialized (yml-parse-string (yml-serialize root)))
             (outer (if (eq key-type 'keyword) ":outer" "outer"))
             (name (if (eq key-type 'keyword) ":name" "name")))
        (should (equal (gethash name (gethash outer serialized)) "café")))))
  (let ((table (make-hash-table :test 'eq)))
    (dolist (key '(nil t :null :false missing disabled))
      (puthash key 1 table))
    (puthash 'null-value 'missing table)
    (puthash 'false-value 'disabled table)
    (let ((parsed (yml-parse-string
                   (yml-serialize table :null-object 'missing
                                  :false-object 'disabled))))
      (dolist (key '(nil t :null :false missing disabled))
        (should (= (gethash (symbol-name key) parsed) 1)))
      (should (eq (gethash "null-value" parsed) :null))
      (should (eq (gethash "false-value" parsed) :false)))))

(ert-deftest yml-native-symbol-alist-serialization ()
  ;; Check parsed nested alists as well as manually constructed symbol keys.
  (let* ((object (yml-parse-string "outer: {name: café}" :object-type 'alist))
         (round-trip (yml-parse-string (yml-serialize object) :object-type 'alist)))
    (should (equal round-trip object)))
  (dolist (sentinels '((:null :false) (missing disabled)))
    (let* ((null-object (car sentinels))
           (false-object (cadr sentinels))
           (object (list (cons 'nil null-object)
                         (cons 't false-object)
                         (cons :null t)
                         (cons :false 4)
                         (cons 'missing 5)
                         (cons 'disabled 6)
                         (cons "string" 7)
                         (cons 8 9)))
           (parsed (yml-parse-string
                    (yml-serialize object :null-object null-object
                                   :false-object false-object))))
      (should (eq (gethash "nil" parsed) :null))
      (should (eq (gethash "t" parsed) :false))
      (should (eq (gethash ":null" parsed) t))
      (should (= (gethash ":false" parsed) 4))
      (should (= (gethash "missing" parsed) 5))
      (should (= (gethash "disabled" parsed) 6))
      (should (= (gethash "string" parsed) 7))
      (should (= (gethash 8 parsed) 9))))
  ;; Alist keyword names retain their colon, unlike plist key names.
  (let* ((object (yml-parse-string "name: value" :object-type 'alist
                                  :object-key-type 'keyword))
         (parsed (yml-parse-string (yml-serialize object))))
    (should (equal (gethash ":name" parsed) "value"))
    (should-not (gethash "name" parsed))))

(ert-deftest yml-native-custom-sentinels ()
  (dolist (sentinels (list (list :null :false)
                           (list 'missing 'disabled)
                           (list nil 'disabled)
                           (list 'missing nil)
                           (list (vector 'missing) (list 'disabled))))
    (let* ((null-object (car sentinels))
           (false-object (cadr sentinels))
           (options (list :null-object null-object :false-object false-object)))
      (dolist (parser '(yml-parse-string yml-parse-string-all))
        (dolist (case (list (cons "null" null-object)
                            (cons "false" false-object)))
          (let ((parsed (apply parser (car case) options)))
            (should (eq (if (eq parser 'yml-parse-string-all)
                            (car parsed) parsed)
                        (cdr case)))))
        (let* ((parsed (apply parser "{values: [null, false, true]}" options))
               (root (if (eq parser 'yml-parse-string-all) (car parsed) parsed))
               (values (gethash "values" root)))
          (should (eq (aref values 0) null-object))
          (should (eq (aref values 1) false-object))
          (should (eq (aref values 2) t))))
      (let ((documents (apply #'yml-parse-string-all
                              "---\nnull\n---\nfalse\n" options)))
        (should (= (length documents) 2))
        (should (eq (car documents) null-object))
        (should (eq (cadr documents) false-object)))
      (should (eq (yml-parse-string (apply #'yml-serialize null-object options))
                  :null))
      (should (eq (yml-parse-string (apply #'yml-serialize false-object options))
                  :false))
      (should (equal (yml-parse-string
                      (apply #'yml-serialize
                             (vector null-object false-object t) options))
                     [:null :false t]))))
  (should (eq (yml-parse-string
               (yml-serialize nil :null-object nil :false-object nil))
              :null)))

(ert-deftest yml-native-serializer-conversions ()
  (let* ((values ["café 🐈" "false" "" 42 1.0 1.25
                  -9223372036854775808 9223372036854775807 t :false :null []])
         (table (make-hash-table :test 'equal)))
    (puthash "values" values table)
    (puthash "child" '(:enabled t) table)
    (dolist (object (list table
                          (list (cons "values" values)
                                (cons "child" '(("enabled" . t))))
                          (list :values values 'child '(:enabled t))))
      (let ((parsed (yml-parse-string (yml-serialize object))))
        (should (= (hash-table-count parsed) 2))
        (should (equal (gethash "values" parsed) values))
        (should (floatp (aref (gethash "values" parsed) 4)))
        (should (eq (gethash "enabled" (gethash "child" parsed)) t))))
    (dolist (empty (list nil (make-hash-table :test 'equal)))
      (let ((parsed (yml-parse-string (yml-serialize empty))))
        (should (hash-table-p parsed))
        (should (= (hash-table-count parsed) 0))))
    (should (equal (yml-parse-string (yml-serialize [])) []))
    (dolist (object '((("key" . 1) ("key" . 2)) (:key 1 :key 2)))
      (should (= (gethash "key" (yml-parse-string (yml-serialize object))) 2)))))

(defun yml-tests--round-trip (yaml expected)
  "Check YAML against EXPECTED alist data, then round-trip all mapping types."
  (should (equal (yml-parse-string yaml :object-type 'alist
                                   :object-key-type 'string) expected))
  (dolist (object-type '(hash-table alist plist))
    (ert-info ((format "Round trip with %s mappings" object-type))
      (let* ((parsed (yml-parse-string yaml :object-type object-type))
             (serialized (yml-serialize parsed)))
        (should (equal (yml-parse-string serialized :object-type 'alist
                                         :object-key-type 'string)
                       expected))))))

(ert-deftest yml-complex-service-config-round-trip ()
  (yml-tests--round-trip
   "# A service configuration with nested block and flow collections.
service:
  name: café-api
  replicas: 3
  enabled: true
  ports:
    - {name: http, port: 8080, tls: false}
    - name: metrics
      port: 9090
      tls: true
  environment:
    RETRIES: '3'
    FEATURE_FLAG: 'false'
    OPTIONAL: null
  healthcheck:
    command: [curl, '--fail', 'http://localhost:8080/health']
    interval: 1.5
  volumes: []
  annotations: {}
"
   '(("service" . (("name" . "café-api")
                   ("replicas" . 3)
                   ("enabled" . t)
                   ("ports" . [(("name" . "http") ("port" . 8080) ("tls" . :false))
                               (("name" . "metrics") ("port" . 9090) ("tls" . t))])
                   ("environment" . (("RETRIES" . "3")
                                     ("FEATURE_FLAG" . "false")
                                     ("OPTIONAL" . :null)))
                   ("healthcheck" . (("command" . ["curl" "--fail" "http://localhost:8080/health"])
                                     ("interval" . 1.5)))
                   ("volumes" . [])
                   ("annotations" . nil))))))

(ert-deftest yml-complex-aliases-and-block-scalars-round-trip ()
  (yml-tests--round-trip
   "defaults: &defaults
  retries: 4
  flags: [true, false, null]
  labels: {region: eu, owner: 'équipe 🐈'}
jobs:
  - name: build
    settings: *defaults
    script: |
      echo \"hello\"
      make test
  - name: deploy
    settings: *defaults
    description: >-
      Deploy the service
      after tests pass.
    version: !!str 2.0
    attempts: !!int 3
"
   '(("defaults" . (("retries" . 4)
                    ("flags" . [t :false :null])
                    ("labels" . (("region" . "eu") ("owner" . "équipe 🐈")))))
     ("jobs" . [(("name" . "build")
                 ("settings" . (("retries" . 4)
                                ("flags" . [t :false :null])
                                ("labels" . (("region" . "eu") ("owner" . "équipe 🐈")))))
                 ("script" . "echo \"hello\"\nmake test\n"))
                (("name" . "deploy")
                 ("settings" . (("retries" . 4)
                                ("flags" . [t :false :null])
                                ("labels" . (("region" . "eu") ("owner" . "équipe 🐈")))))
                 ("description" . "Deploy the service after tests pass.")
                 ("version" . "2.0")
                 ("attempts" . 3))]))))

(ert-deftest yml-complex-multi-document-round-trip ()
  (let ((yaml "---
kind: Config
metadata: {name: production, labels: {team: platform}}
data:
  endpoints: [https://api.example.test, https://backup.example.test]
  timeout: 2.5
---
- name: rollout
  steps:
    - {action: deploy, dry_run: false}
    - {action: verify, checks: [health, metrics]}
- name: cleanup
  steps: []
...\n")
        (expected
         '((("kind" . "Config")
            ("metadata" . (("name" . "production")
                           ("labels" . (("team" . "platform")))))
            ("data" . (("endpoints" . ["https://api.example.test" "https://backup.example.test"])
                       ("timeout" . 2.5))))
           [(("name" . "rollout")
             ("steps" . [(("action" . "deploy") ("dry_run" . :false))
                         (("action" . "verify") ("checks" . ["health" "metrics"]))]))
            (("name" . "cleanup") ("steps" . []))])))
    (should (equal (yml-parse-string-all yaml :object-type 'alist
                                       :object-key-type 'string) expected))
    (dolist (object-type '(hash-table alist plist))
      (ert-info ((format "Multi-document round trip with %s mappings" object-type))
        (let* ((documents (yml-parse-string-all yaml :object-type object-type))
               (serialized (mapconcat #'yml-serialize documents "\n")))
          (should (equal (yml-parse-string-all serialized :object-type 'alist
                                             :object-key-type 'string)
                         expected)))))))

(ert-deftest yml-native-errors-and-recovery ()
  (dolist (parser '(yml-parse-string yml-parse-string-all))
    (should-error (funcall parser "[") :type 'yml-parse-error)
    (should-error (funcall parser "&loop [*loop]") :type 'yml-parse-error)
    (should-error (funcall parser "!!int invalid") :type 'yml-parse-error)
    (should-error (funcall parser "7: value" :object-type 'plist)
                  :type 'yml-non-string-key)
    (should-error (funcall parser "1" :object-type 'invalid) :type 'error)
    (should-error (funcall parser "1" :array-type 'invalid) :type 'error)
    (should-error (funcall parser 42) :type 'wrong-type-argument)
    (should (equal (funcall parser "42")
                   (if (eq parser 'yml-parse-string-all) '(42) 42))))
  (should-error (yml-parse-string "---\n1\n---\n2\n")
                :type 'yml-trailing-content)
  (should (equal (yml-parse-string-all "---\n1\n---\n2\n") '(1 2)))
  (dolist (object (list 'unsupported (current-buffer)
                        '(:key) '(:key 1 . tail)
                        9223372036854775808 -9223372036854775809))
    (ert-info ((format "Serialization of %S" object))
      (should-error (yml-serialize object) :type 'yml-serialization-error)
      ;; Check if poisoned from earlier runs
      (should (equal (yml-parse-string (yml-serialize [1])) [1]))))
  (should-error (yml-serialize '("not-a-symbol" 1)) :type 'wrong-type-argument)
  (should (equal (yml-parse-string (yml-serialize [2])) [2])))

(provide 'yml-tests)
;;; yml-tests.el ends here
