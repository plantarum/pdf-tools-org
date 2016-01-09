;;; pdf-tools-org.el --- pdf-tools and org-mode integration

;;; Commentary:
;; pdf-tools-org provides integration between pdf-tools and org-mode.
;; The main features are importing and exporting pdf annotations from/to
;; org files.

;;; Code:

(require 'pdf-tools)

(defconst pdf-tools-org-exportable-properties
  (list 'page 'edges 'id 'flags 'color 'modified 'label 'subject 'opacity 'created 'markup-edges 'icon))

;; some properties are not changeable by default.
;; we miss some information when importing, such as creation date.
(defconst pdf-tools-org-importable-properties
  (list 'contents 'edges 'flags 'color 'label 'opacity 'icon))

(defun pdf-tools-org-edges-to-region (edges)
  "Attempt to get 4-entry region \(LEFT TOP RIGHT BOTTOM\) from several EDGES.
We need this to import annotations and to get marked-up text, because
annotations are referenced by its edges, but functions for these tasks
need region."
  (let ((left0 (nth 0 (car edges)))
        (top0 (nth 1 (car edges)))
        (bottom0 (nth 3 (car edges)))
        (top1 (nth 1 (car (last edges))))
        (right1 (nth 2 (car (last edges))))
        (bottom1 (nth 3 (car (last edges))))
        (n (safe-length edges)))
    ;; we try to guess the line height to move
    ;; the region away from the boundary and
    ;; avoid double lines
    (list left0
          (+ top0 (/ (- bottom0 top0) 3))
          right1
          (- bottom1 (/ (- bottom1 top1) 3)))))

(defun pdf-tools-org-export-to-org ()
  "Export annotations to an Org file."
  (interactive)
  (let ((annots (sort (pdf-annot-getannots) 'pdf-annot-compare-annotations))
        (filename (format "%s.org"
                          (file-name-sans-extension
                           (buffer-name))))
        (buffer (current-buffer)))
    (with-temp-buffer
      (insert (concat "#+TITLE: Notes for " (file-name-sans-extension filename)))
      (mapc
       (lambda (annot) ;; traverse all annotations
         (progn
           (org-insert-heading-respect-content)
           (insert (symbol-name (pdf-annot-get-id annot)))
           (insert (concat " :" (symbol-name (pdf-annot-get-type annot)) ":"))
           ;; insert text from marked-up region in an org-mode quote
           (when (pdf-annot-get annot 'markup-edges)
             (insert (concat "\n#+BEGIN_QUOTE\n"
                             (with-current-buffer buffer
                               (pdf-info-gettext (pdf-annot-get annot 'page)
                                                 (pdf-tools-org-edges-to-region
                                                  (pdf-annot-get annot 'markup-edges))))
                             "\n#+END_QUOTE")))
           (insert (concat "\n\n" (pdf-annot-get annot 'contents)))
           ;; set org properties for each of the remaining fields
           (mapcar
            '(lambda (field) ;; traverse all fields
               (when (member (car field) pdf-tools-org-exportable-properties)
                 (org-set-property (symbol-name (car field))
                                   (format "%s" (cdr field)))))
            annot)))
       annots)
      (org-set-tags 1)
      (write-file filename t))))

(defun pdf-tools-org-import-from-org (orgfile)
  "Import annotations from an Org file."
  (interactive (list (ido-read-file-name "Org file to import from: ")))
  (let ((pdfbuffer (current-buffer)))
    (save-window-excursion
      (find-file orgfile)
      (goto-char (point-min))
      (org-next-visible-heading 1)
      (while (/= (point) (buffer-end 1)) ;; traverse org file
        (let ((properties (list)))
          ;; build list of properties
          (mapc
           (lambda (x)
             (let ((propname (intern (downcase (car x)))) (propval (cdr x)))
               (when (member propname pdf-tools-org-exportable-properties)
                 (push
                  (cons propname
                        (cond ;; convert from string to proper types
                         ((member propname (list 'page 'flags 'opacity)) (string-to-number propval))
                         ((member propname (list 'id)) (intern propval))
                         ((string-equal propval "nil") nil)
                         ((member propname (list 'edges 'modified))
                          (mapcar 'string-to-number (split-string propval " \\|(\\|)" t)))
                         ;; markup-edges is a list of lists of 4
                         ((member propname (list 'markup-edges))
                          (mapcar (lambda (x)
                                    (mapcar 'string-to-number (split-string x " \\|(\\|)" t)))
                                  (split-string propval "\) \(")))
                         (t propval)))
                  properties))))
           (org-entry-properties))
          ;; include 'type
          (push (cons 'type (intern (car (org-get-tags))))
                properties)
          ;; add contents -- they are the subtree text, after the properties
          (push (cons 'contents
                      (let ((beg (save-excursion (re-search-forward ":END:\n") (point)))
                            (end (save-excursion (org-next-visible-heading 1) (point))))
                        (buffer-substring-no-properties beg end)))
                properties)
          ;; add annotation
          (with-current-buffer pdfbuffer
            (pdf-annot-add-annotation (pdf-annot-get properties 'type)
                                      (if (eq (pdf-annot-get properties 'type) 'text)
                                          (pdf-annot-get properties 'edges)
                                        (pdf-tools-org-edges-to-region (pdf-annot-get properties 'markup-edges)))
                                      (delq nil (mapcar
                                                 (lambda (x)
                                                   (if (member (car x) pdf-tools-org-importable-properties)
                                                       x nil))
                                                 properties))
                                      (pdf-annot-get properties 'page)))
          (org-next-visible-heading 1))))))


(provide 'pdf-tools-org)
;;; pdf-tools-org ends here