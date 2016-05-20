;;; f3.el --- helm interface for searching files really fast

;; Keywords: find, files, helm

;;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'helm)

;;; functions to parse patterns into an AST
;;; TODO: defcustom for default input mode, and persist across combinators
(defconst f3-input-modes
  '((text . f3-create-text-pattern)
    (regex . f3-create-regex-pattern)
    (find . f3-create-find-pattern)
    (filetype . f3-create-filetype-pattern))
  "Modes which interpret the current `helm-pattern' differently.")

(defun f3-create-text-pattern (pat)
  (let ((texts (helm-mm-split-pattern pat)))
    (cl-reduce
     (lambda (parsed1 parsed2) (list :and parsed1 parsed2))
     (cl-mapcar (lambda (pat) (list :text pat)) texts))))

(defun f3-create-regex-pattern (pat)
  (let ((texts (helm-mm-split-pattern pat)))
    (cl-reduce
     (lambda (parsed1 parsed2) (list :and parsed1 parsed2))
     (cl-mapcar (lambda (pat) (list :regex pat)) texts))))

(defun f3-create-find-pattern (pat)
  "Assumes correctness of pattern PAT."
  (list :raw pat))

(defconst f3-valid-filetype-patterns '("b" "c" "d" "f" "l" "p" "s")
  "Valid filetype arguments to unix find.")

(defun f3-create-filetype-pattern (pat)
  (unless (member pat f3-valid-filetype-patterns)
    (error (format "%s %s" "invalid filetype pattern" pat)))
  (list :filetype pat))

(defconst f3-combinators '(:and :or))

(defun f3-do-complement (ast do-complement)
  (if do-complement (list :not ast) ast))

(defun f3-pattern-to-parsed-arg (pattern mode complement)
  (let ((process-input-fn (assoc mode f3-input-modes)))
    (if process-input-fn
        (f3-do-complement (funcall process-input-fn pattern) complement)
      (error (format "%s %S" "invalid mode" mode)))))

(defun f3-maybe-lowercase-generate (base pat)
  (let ((cleaned-pat (replace-regexp-in-string "\"" "" pat)))
    ;; we generate base, so no injection
    (if (string-match-p "[[:upper:]]" cleaned-pat)
        (format "-%s \"%s\"" base cleaned-pat)
      (format "-i%s \"%s\"" base cleaned-pat))))

(defun f3-parsed-to-command (parsed-args)
  "Transform PARSED-ARGS to a raw find command."
  (pcase parsed-args
    ;; operators
    (`(:and . ,args)
     (cl-reduce (lambda (str1 str2) (format "\\( %s \\) -and \\( %s \\)"
                                            str1 str2))
                (cl-mapcar #'f3-parsed-to-command args)))
    (`(:or . ,args)
     (cl-reduce (lambda (str1 str2) (format "\\( %s \\) -or \\( %s \\)"
                                            str1 str2))
                (cl-mapcar #'f3-parsed-to-command args)))
    (`(:not ,thing) (format "-not \\( %s \\)") (f3-parsed-to-command thing))
    ;; modes
    (`(:text ,thing) (f3-maybe-lowercase-generate "name" thing))
    (`(:regex ,thing) (f3-maybe-lowercase-generate "regex" thing))
    (`(:raw ,thing) thing)
    (`(:filetype ,thing) (format "-type %s" thing))
    (_  parsed-args)))

;;; TODO: defcustom this
(defconst f3-default-combinator :and)
(defvar-local f3-current-combinator f3-default-combinator)
;;; TODO: defcustom this
(defconst f3-default-mode :text)
(defvar-local f3-current-mode f3-default-mode)

;;; TODO: restart `helm-pattern' with whatever was in it before `f3-open-paren'
;;; or `f3-close-paren' was called, after calling it
(defun f3-open-paren (dir cur-cmd paren-stack)
  (f3-do dir nil (cons (list f3-current-combinator cur-cmd) paren-stack)
         f3-current-combinator f3-current-mode))

(defun f3-close-paren (dir cur-cmd paren-stack)
  (let ((cur-paren (car paren-stack))
        (upper (cdr paren-stack)))
    (cl-destructuring-bind (comb cmd) cur-paren
      (f3-do dir (list comb cmd cur-cmd) upper f3-current-combinator
             f3-current-mode))))

(defun f3-close-parens-to-make-command (cur-cmd paren-stack)
  (cl-reduce
   (lambda (cur stack-el)
     (cl-destructuring-bind (comb cmd) stack-el (list comb cur cmd)))
   paren-stack
   :initial-value cur-cmd))

;;; TODO: defcustom this
(defconst f3-default-complement nil)
(defvar-local f3-current-complement f3-default-complement)

;;; TODO: defcustom this
(defconst f3-find-program "find")

(defun f3-do (dir cur-cmd paren-stack)
  "CUR-CMD is a list of parsed arguments, not plain text."
  ;; turn current pattern into something for find, if non-blank
  (let* ((current-pattern
          (unless (string-empty-p helm-pattern)
            (f3-pattern-to-parsed-arg
             helm-pattern f3-current-mode f3-current-complement)))
         (combined-pattern (list f3-current-combinator cur-cmd current-pattern))
         (complete-pattern
          (f3-close-parens-to-make-command combined-pattern paren-stack))
         (find-cmd
          (format "%s \"%s\" %s"
                  f3-find-program dir (f3-parsed-to-command complete-pattern))))
    ;; TODO: run helm with find as an async source!
    ))

;;; TODO: make defcustom for f3's default directory

;;;###autoload
(defun f3 (start-dir)
  (interactive (list default-directory))
  ;; in case user modifies defcustoms after this file is loaded
  (setq-local
   f3-current-combinator f3-default-combinator
   f3-current-mode f3-default-mode
   f3-current-complement f3-default-complement)
  (f3-do ))

(provide 'f3)
;;; f3.el ends here
