;; Copyright 2013 Thomas Järvstrand <tjarvstrand@gmail.com>
;;
;; This file is part of EDTS.
;;
;; EDTS is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Lesser General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; EDTS is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Lesser General Public License for more details.
;;
;; You should have received a copy of the GNU Lesser General Public License
;; along with EDTS. If not, see <http://www.gnu.org/licenses/>.
;;
;; Debugger interaction code for EDTS

;; Window configuration to be restored when quitting debug mode

(require 'edts_debug-list-breakpoint-mode)
(require 'edts_debug-list-interpreted-mode)
(require 'edts_debug-list-processes-mode)

(defface edts_debug-breakpoint-active-face
  '((((class color) (background dark)) (:background "dark blue"))
    (((class color) (background light)) (:background "light blue"))
    (t (:bold t)))
  "Face used for marking warning lines."
  :group 'edts)

(defface edts_debug-breakpoint-inactive-face
  '((((class color) (background dark)) (:background "grey"))
    (((class color) (background light)) (:background "light grey"))
    (t (:bold t)))
  "Face used for marking warning lines."
  :group 'edts)

(defconst edts_debug-breakpoint-face-prio 800
  "Face priority for breakpoints.")

(defvar edts_debug--interpret-request-buffer nil
  "Buffer for requests to attach to the debugged process. One such
request should always be outstanding if we are not already attached.")

(defun edts_debug-init ()
  "Initialize edts_debug."
  ;; Keys
  (define-key edts-mode-map "\C-c\C-db"   'edts_debug-break)
  (define-key edts-mode-map "\C-c\C-di"   'edts_debug-interpret)
  (define-key edts-mode-map "\C-c\C-d\M-b" 'edts_debug-list-breakpoints)
  (define-key edts-mode-map "\C-c\C-d\M-i" 'edts_debug-list-interpreted)
  (define-key edts-mode-map "\C-c\C-d\M-p" 'edts_debug-list-processes)
  (add-hook 'edts-after-node-init-hook 'edts_debug-after-node-init-hook)
  (add-hook 'edts-node-down-hook 'edts_debug-node-down-hook)
  (add-hook 'edts-server-down-hook 'edts_debug-server-down-hook))

(defun edts_debug-after-node-init-hook ()
  "Hook to run after node initialization."
  (edts_debug-sync))

(defun edts_debug-node-down-hook (node)
  "Hook to run after node initialization."
  (let ((interpreted (assoc node edts_debug-interpreted-alist))
        (breakpoints (assoc node edts_debug-breakpoint-alist))
        (processes   (assoc node edts_debug-processes-alist)))
    (setq edts_debug-interpreted-alist
          (delete interpreted edts_debug-interpreted-alist))
    (setq edts_debug-breakpoint-alist
          (delete breakpoints edts_debug-breakpoint-alist))
    (setq edts_debug-processes-alist
          (delete processes edts_debug-processes-alist))
    (run-hooks 'edts_debug-after-sync-hook)))

(defun edts_debug-server-down-hook ()
  "Hook to run after node initialization."
  (setq edts_debug-interpreted-alist nil)
  (setq edts_debug-breakpoint-alist nil)
  (setq edts_debug-processes-alist nil)
  (run-hooks 'edts_debug-after-sync-hook))

(defun edts_debug-format-mode-line ()
  "Formats the edts_debug mode line string for display."
  (concat (propertize edts_debug-mode-line-string 'face `(:box t)) " "))

(defun edts_debug-buffer-init ()
  "edts_debug buffer-specific initialization."
  (add-to-list 'mode-line-buffer-identification
               '(edts-mode (:eval (edts_debug-format-mode-line)))
               t))

(defvar edts_debug-mode-line-string ""
  "The string with edts_debug related information to display in
the mode-line.")
(make-variable-buffer-local 'edts_debug-mode-line-string)

(defvar edts_debug-breakpoint-alist nil
  "Alist with breakpoints for each node. Each value is an alist with one
key for each interpreted module the value of which is a list of
breakpoints for that module.")

(defvar edts_debug-interpreted-alist nil
  "Alist with interpreted modules for each node. Each value is a list
of strings.")

(defvar edts_debug-processes-alist nil
  "Alist with all debugged processes for each node. Each value is a list
of strings.")

(defvar edts_debug-after-sync-hook nil
  "Hook to run after synchronizing debug information (interpreted
modules, breakpoints and debugged processes).")

(defun edts_debug-sync ()
  "Synchronize edts_debug data."
  (interactive)
  (edts_debug-sync-interpreted-alist)
  (edts_debug-sync-breakpoint-alist)
  (edts_debug-sync-processes-alist)
  (run-hooks 'edts_debug-after-sync-hook))

(defun edts_debug-event-handler (node class type info)
  "Handles erlang-side debugger events"
  (case type
    (interpret     (let ((module (cdr (assoc 'module info))))
                     (edts-log-info "%s is now interpreted on %s" module node))
                   (edts_debug-sync-interpreted-alist))
    (no_interpret  (let ((module (cdr (assoc 'module info))))
                     (edts-log-info "%s is no longer interpreted on %s"
                                    module
                                    node))
                   (edts_debug-sync-interpreted-alist))
    (new_break     (let ((module (cdr (assoc 'module info)))
                         (line (cdr (assoc 'line info))))
                     (edts-log-info "breakpoint set on %s:%s on %s"
                                    module
                                    line
                                    node)
                     (edts_debug-sync-breakpoint-alist)))
    (delete_break  (let ((module (cdr (assoc 'module info)))
                         (line (cdr (assoc 'line info))))
                     (edts-log-info "breakpoint unset on %s:%s on %s"
                                    module
                                    line
                                    node)
                     (edts_debug-sync-breakpoint-alist)))
    (break_options (let ((module (cdr (assoc 'module info)))
                         (line (cdr (assoc 'line info))))
                     (edts-log-info "breakpoint options updated on %s:%s on %s"
                                    module
                                    line
                                    node)
                     (edts_debug-sync-breakpoint-alist)))
    (no_break      (let ((module (cdr (assoc 'module info))))
                     (edts-log-info "All breakpoints inn %s deleted on %s"
                                    module
                                    node)
                     (edts_debug-sync-breakpoint-alist)))
    (new_process   (edts_debug-sync-processes-alist))
    (new_status    (edts_debug-sync-processes-alist)))
  (run-hooks 'edts_debug-after-sync-hook))
(edts-event-register-handler 'edts_debug-event-handler 'edts_debug)

(defun edts_debug-update-buffers ()
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when edts-mode
        (let ((node   (edts-node-name))
              (module (ferl-get-module)))
          (when (and node module)
            (edts_debug-update-buffer-info node module)))))))
(add-hook 'edts_debug-after-sync-hook 'edts_debug-update-buffers)


(defun edts_debug-sync-interpreted-alist ()
  "Synchronizes `edts_debug-interpreted-alist'."
  (setq edts_debug-interpreted-alist
        (loop for node in (edts-get-nodes)
              collect (cons node (edts_debug-interpreted-modules node)))))

(defun edts_debug-sync-breakpoint-alist ()
  "Synchronizes `edts_debug-breakpoint-alist'."
  (setq edts_debug-breakpoint-alist
        (loop for node in (edts-get-nodes)
              for node-breakpoints = (edts_debug-all-breakpoints node)
              when node-breakpoints
              collect (loop
                       for breakpoint in node-breakpoints
                       with breakpoints
                       for module     = (cdr (assoc 'module breakpoint))
                       for old-elt    = (assoc module breakpoints)
                       ;; To get the breakpoint representation, delete the
                       ;; module key/value of the breakpoint alist (since that
                       ;; is the key in the outer alist)
                       for break-list = (cons
                                         (delete
                                          (cons 'module module) breakpoint)
                                         (cdr old-elt))
                       for new-elt    = (cons module break-list)
                       do (setq breakpoints
                                (cons new-elt
                                      (delete old-elt breakpoints)))
                       finally (return (cons node breakpoints))))))

(defun edts_debug-sync-processes-alist ()
  "Synchronizes `edts_debug-processes-alist'."
  (setq edts_debug-processes-alist
        (loop for node in (edts-get-nodes)
              for procs = (edts_debug-all-processes node)
              collect (cons
                       node
                       (cdr (assoc 'processes procs))))))

(defun edts_debug-continue (node pid)
  "Send a continue-command to PID on NODE."
  (edts_debug--cmd node pid 'continue))

(defun edts_debug--cmd (node pid cmd)
  "Send the command CMD to PID on NODE."
  (let* ((resource  (list "plugins"
                          "debugger"
                          "nodes" node
                          "processes" pid
                          "command"))
         (rest-args (list (cons "cmd" (symbol-name cmd))))
         (reply     (edts-rest-post resource rest-args))
         (res       (assoc 'result reply)))
    (unless (equal res '(result "204" "Created"))
      (null (edts-log-error "Unexpected reply %s" res)))))

(defun edts_debug-update-buffer-info (node module)
  (if (member module (cdr (assoc node edts_debug-interpreted-alist)))
      (setq edts_debug-mode-line-string "Interpreted")
    (setq edts_debug-mode-line-string ""))
  (force-mode-line-update)

  (edts-face-remove-overlays '(edts_debug-breakpoint))
  (let ((breaks (cdr (assoc module
                            (cdr (assoc node edts_debug-breakpoint-alist))))))
    (loop for break in breaks
        for line      = (cdr (assoc 'line      break))
        for status    = (cdr (assoc 'status    break))
        for trigger   = (cdr (assoc 'trigger   break))
        for condition = (cdr (assoc 'condition break))
        for face      = (if (string= status "active")
                            'edts_debug-breakpoint-active-face
                          'edts_debug-breakpoint-inactive-face)
        for fmt       = "Breakpoint status: %s, trigger: %s, condition: %s"
        do
        (edts-face-display-overlay face
                                   line
                                   (format fmt status trigger condition)
                                   'edts_debug-breakpoint
                                   edts_debug-breakpoint-face-prio
                                   t))))

(defun edts_debug-interpret (&optional node module interpret)
  "Set interpretation state for MODULE on NODE according to INTERPRET.
NODE and MODULE default to the values associated with current buffer.
If INTERPRET is nil stop intepreting; if it is t interpret MODULE; any
other value toggles interpretation, which is the default behaviour."
  (interactive (list
                nil
                nil
                'toggle))
  (let* ((module    (or module (ferl-get-module)))
         (node-name (or node (edts-node-name)))
         (interpret (cond
                     ((eq interpret t) "true")
                     ((null interpret) "false")
                     (t                "toggle")))
         (resource  (list "plugins"
                          "debugger"
                          "nodes" node-name
                          "modules" module))
         (rest-args (list (cons "interpret" interpret)))
         (reply     (edts-rest-post resource rest-args))
         (res       (assoc 'result reply)))
    (cond
     ((equal res '(result "403" "Forbidden"))
      (null (edts-log-error "%s is not interpretable" module)))
     ((not (equal res '(result "201" "Created")))
      (null (edts-log-error "Unexpected reply: %s" (cdr res)))))))

(defun edts_debug-break (&optional node module line break)
  "Set breakpoint state for LINE in MODULE on NODE according to
BREAK. NODE and MODULE default to the values associated with current
buffer. If BREAK is nil remove any breakpoint; if it is t set a
breakpoint if one doesn't already exist; any other value toggles
breakpoint existence at LINE, which is the default behaviour."
  (interactive (list nil
                     nil
                     nil
                     'toggle))
  (let* ((node-name (or node (edts-node-name)))
         (module    (or module (ferl-get-module)))
         (line      (or line (line-number-at-pos)))
         (break     (cond
                     ((eq break t) "true")
                     ((null break) "false")
                     (t            "toggle")))
         (resource  (list "plugins"
                          "debugger"
                          "nodes"   node-name
                          "modules" module
                          "breakpoints" (number-to-string line)))
         (rest-args (list (cons "break" break)))
         (reply     (edts-rest-post resource rest-args))
         (res       (assoc 'result reply)))
    (unless (equal res '(result "201" "Created"))
      (null (edts-log-error "Unexpected reply: %s" (cdr res))))))

(defun edts_debug-breakpoints (&optional node module)
  "Return a list of all breakpoint states in module on NODE. NODE and
MODULE default to the value associated with current buffer."
  (let* ((node-name (or node (edts-node-name)))
         (module    (or module (ferl-get-module)))
         (resource  (list "plugins"
                          "debugger"
                          "nodes"   node-name
                          "modules" module
                          "breakpoints"))
         (rest-args nil)
         (reply     (edts-rest-get resource rest-args))
         (res       (assoc 'result reply)))
    (if (not (equal res '(result "200" "OK")))
        (null
         (edts-log-error "Unexpected reply: %s" (cdr res)))
      (cdr (assoc 'body reply)))))

(defun edts_debug-all-breakpoints (&optional node)
  "Return a list of all breakpoint states on NODE. NODE defaults to the
value associated with current buffer."
  (let* ((node-name (or node (edts-node-name)))
         (resource  (list "plugins"
                          "debugger"
                          "nodes"   node-name
                          "breakpoints"))
         (rest-args nil)
         (reply     (edts-rest-get resource rest-args))
         (res       (assoc 'result reply)))
    (if (not (equal res '(result "200" "OK")))
        (null
         (edts-log-error "Unexpected reply: %s" (cdr res)))
      (cdr (assoc 'body reply)))))

(defun edts_debug-all-processes (&optional node)
  "Return a list of all breakpoint states on NODE. NODE defaults to the
value associated with current buffer."
  (let* ((node-name (or node (edts-node-name)))
         (resource  (list "plugins"
                          "debugger"
                          "nodes"   node-name
                          "processes"))
         (rest-args nil)
         (reply     (edts-rest-get resource rest-args))
         (res       (assoc 'result reply)))
    (if (not (equal res '(result "200" "OK")))
        (null
         (edts-log-error "Unexpected reply: %s" (cdr res)))
      (cdr (assoc 'body reply)))))


(defun edts_debug-interpretedp (&optional node module)
  "Return non-nil if MODULE is interpreted on NODE. NODE and MODULE
default to the values associated with current buffer."
  (let* ((module    (or module (ferl-get-module)))
         (node-name (or node (edts-node-name)))
         (resource  (list "plugins"
                          "debugger"
                          "nodes" node-name
                          "modules" module))
         (rest-args nil)
         (reply     (edts-rest-get resource rest-args))
         (res       (assoc 'result reply)))
    (if (not (equal res '(result "200" "OK")))
        (null
         (edts-log-error "Unexpected reply: %s" (cdr res)))
      (cdr (assoc 'interpreted (cdr (assoc 'body reply)))))))

(defun edts_debug-interpreted-modules (&optional node)
  "Return a list of all modules that are interpreted on NODE. NODE
default to the values associated with current buffer."
  (let* ((node-name (or node (edts-node-name)))
         (resource  (list "plugins"
                          "debugger"
                          "nodes" node-name
                          "modules"))
         (rest-args nil)
         (reply     (edts-rest-get resource rest-args))
         (res       (assoc 'result reply)))
    (if (not (equal res '(result "200" "OK")))
        (null
         (edts-log-error "Unexpected reply: %s" (cdr (assoc 'result res))))
      (cdr (assoc 'modules (cdr (assoc 'body reply)))))))

(defun edts_debug-process-continue (node-name pid)
  "Send a continue-command to the debugged process with PID on NODE."
  (edts_debug-process-command 'continue node-name pid))

(defun edts_debug-process-command (command node-name pid)
  "Send COMMAND to the debugged process with PID on NODE. Command is
one of continue...tbc."
  (let* ((resource (list "plugins"   "debugger"
                         "nodes"     node-name
                         "processes" pid
                         "command"))
         (args  (list (cons "cmd" (symbol-name command))))
         (reply (edts-rest-post resource args))
         (res   (car (cdr (assoc 'result reply)))))
    (unless (equal res "204")
      (null
       (edts-log-error "Unexpected reply: %s" (cdr (assoc 'result res)))))))



(when (member 'ert features)

  (require 'edts-test)
  (edts-test-add-suite
   ;; Name
   edts_debug-suite
   ;; Setup
   (lambda ()
     (edts-test-setup-project edts-test-project1-directory
                              "test"
                              nil))
   ;; Teardown
   (lambda (setup-config)
     (edts-test-teardown-project edts-test-project1-directory)))

  (edts-test-case edts_debug-suite edts_debug-basic-test ()
    "Basic debugger setup test"
    (let ((eproject-prefer-subproject t))
      (find-file (car (edts-test-project1-modules)))

      (should-not (edts_debug-interpretedp))
      (edts_debug-interpret nil nil 't)
      (should (edts_debug-interpretedp))
      (should-not (edts_debug-breakpoints))
      (edts_debug-break nil nil nil t)
      (should (eq 1 (length (edts_debug-breakpoints)))))))

;; (defvar *edts_debug-window-config-to-restore* nil)

;; (defvar *edts_debug-last-visited-file* nil)

;; (defcustom edts_debug-interpret-after-saving t
;;   "Set to a non-NIL value if EDTS should automatically interpret a module
;; after save-and-compile"
;;   :group 'edts)

;; (defun edts_debug--is-node-interpreted (node-name)
;;   "Reports if the node for the current project is running interpreted code"
;;   (let* ((state (edts-is-node-interpreted node-name)))
;;     (eq (cdr (assoc 'state state)) t)))

;; (defun edts_debug-toggle-interpret-minor-mode ()
;;   (interactive)
;;   (mapcar #'(lambda (buffer)
;; 	      (with-current-buffer buffer
;; 		(when (and edts-mode (eproject-name))
;;                   (edts-int-mode 'toggle))))
;; 	  (buffer-list)))

;; ;; TODO: extend breakpoint toggling to add a breakpoint in every clause
;; ;; of a given function when the line at point is a function clause.
;; (defun edts_debug-toggle-breakpoint ()
;;   "Enables or disables breakpoint at point"
;;   (interactive)
;;   (let* ((line-number (edts_debug--line-number-at-point))
;;          (node-name  (or (edts-node-name)
;;                          (edts_debug-buffer-node-name)))
;;          (state (edts-toggle-breakpoint node-name
;;                                         (erlang-get-module)
;;                                         (number-to-string line-number)))
;;          (result (cdr (assoc 'result state))))
;;     (edts_debug-update-breakpoints)
;;     (edts-log-info "Breakpoint %s at %s:%s"
;;                    result
;;                    (cdr (assoc 'module state))
;;                    (cdr (assoc 'line state)))))

;; (defun edts_debug-step ()
;;   "Steps (into) when debugging"
;;   (interactive)
;;   (edts-log-info "Step")
;;   (edts_debug-handle-debugger-reply
;;    (edts-step-into (edts_debug-buffer-node-name))))

;; (defun edts_debug-step-out ()
;;   "Steps out of the current function when debugging"
;;   (interactive)
;;   (edts-log-info "Step out")
;;   (edts_debug-handle-debugger-reply
;;    (edts-step-out (edts_debug-buffer-node-name))))

;; (defun edts_debug-continue ()
;;   "Continues execution when debugging"
;;   (interactive)
;;   (edts-log-info "Continue")
;;   (edts_debug-handle-debugger-reply
;;    (edts-continue (edts_debug-buffer-node-name))))

;; (defun edts_debug-quit ()
;;   "Quits debug mode"
;;   (interactive)
;;   (edts_debug-stop (edts_debug-buffer-node-name))
;;   (edts_debug--kill-debug-buffers)
;;   (set-window-configuration *edts_debug-window-config-to-restore*)
;;   (setf *edts_debug-window-config-to-restore* nil)
;;   (edts_debug-update-breakpoints))

;; (defun edts_debug-start-debugging ()
;;   (interactive)
;;   (edts_debug-enter-debug-mode)
;;   (edts-wait-for-debugger (edts_debug-buffer-node-name)))

;; (defun edts_debug-enter-debug-mode (&optional file line)
;;   "Convenience function to setup and enter debug mode"
;;   (edts_debug-save-window-configuration)
;;   (edts_debug-enter-debug-buffer file line)
;;   (delete-other-windows)
;;   (edts_debug-mode)
;;   (edts_debug--create-auxiliary-buffers))

;; (defun edts_debug--line-number-at-point ()
;;   "Get line number at point"
;;   (interactive)
;;   (save-restriction
;;     (widen)
;;     (save-excursion
;;       (beginning-of-line)
;;       (1+ (count-lines 1 (point))))))

;; (defun edts_debug-save-window-configuration ()
;;   "Saves current window configuration if not currently in an Edts_Debug buffer"
;;   (if (and (not (equal (buffer-local-value 'major-mode (current-buffer)) 'edts_debug-mode))
;;            (null *edts_debug-window-config-to-restore*))
;;       (setq *edts_debug-window-config-to-restore*
;;             (current-window-configuration))))

;; (defun edts_debug-enter-debug-buffer (file line)
;;   "Helper function to enter a debugger buffer with the contents of FILE"
;;   (if (and file (stringp file))
;;       (progn (pop-to-buffer (edts_debug-make-debug-buffer-name file))
;;              (when (not (equal *edts_debug-last-visited-file* file))
;;                (setq buffer-read-only nil)
;;                (erase-buffer)
;;                (insert-file-contents file)
;;                (setq buffer-read-only t))
;;              (setq *edts_debug-last-visited-file* file))
;;     (progn
;;       (let ((file (buffer-file-name)))
;;         (pop-to-buffer (edts_debug-make-debug-buffer-name file))
;;         (erase-buffer)
;;         (insert-file-contents file))
;;       (setq *edts_debug-last-visited-file* nil)))
;;   (edts-face-remove-overlays '("edts_debug-current-line"))
;;   (when (numberp line)
;;     (edts-face-display-overlay 'edts-face-debug-current-line
;;                                line
;;                                "EDTS debugger current line"
;;                                "edts_debug-current-line"
;;                                20
;;                                t))
;;   (setq *edts_debugger-buffer* (current-buffer))
;;   (edts_debug-update-breakpoints))


;; (defvar edts_debug-mode-keymap
;;   (let ((map (make-sparse-keymap)))
;;     (define-key map (kbd "SPC") 'edts_debug-toggle-breakpoint)
;;     (define-key map (kbd "s")   'edts_debug-step)
;;     (define-key map (kbd "o")   'edts_debug-step-out)
;;     (define-key map (kbd "c")   'edts_debug-continue)
;;     (define-key map (kbd "q")   'edts_debug-quit)
;;     map))

;; (define-derived-mode edts_debug-mode erlang-mode
;;   "EDTS debug mode"
;;   "Major mode for debugging interpreted Erlang code using EDTS"
;;   (setq buffer-read-only t)
;;   (setq mode-name "edts_debug")
;;   (use-local-map edts_debug-mode-keymap))

;; (define-minor-mode edts-int-mode
;;   "Toggle code interpretation for the project node belonging to the current
;; buffer. This means all modules (except those belonging to OTP and to the
;; applications excluded explicity in the project's configuration will
;; be interpreted"
;;   :init-value nil
;;   :lighter " EDTS-interpreted"
;;   :group edts
;;   :require edts-mode
;;   :after-hook (let* ((node-name (or (edts-node-name)
;; 				    (edts_debug-buffer-node-name)))
;; 		     (exclusions (edts-project-interpretation-exclusions))
;; 		     (interpretedp (edts_debug--is-node-interpreted node-name)))
;; 		(if (and (not edts-int-mode) interpretedp)
;; 		    (edts-set-node-interpretation node-name nil exclusions)
;; 		  (progn (edts-log-info "Interpreting all loaded modules (this might take a while)...")
;; 			 (edts-set-node-interpretation node-name t exclusions))))
;; )

;; (defun edts_debug--create-auxiliary-buffers ()
;;   (let ((buffer-width 81))
;;     (split-window nil buffer-width 'left)
;;     (switch-to-buffer "*Edts_Debugger Bindings*")
;;     (edts_debug--update-bindings '())
;;     (edts_debug-mode)
;;     (other-window 1)))

;; (defun edts_debug--kill-debug-buffers ()
;;   (dolist (buf (edts_debug--match-buffers
;;                 #'(lambda (buffer)
;;                     (let* ((name (buffer-name buffer))
;;                            (match
;;                             (string-match "^*Edts_Debugger."
;;                                           name)))
;;                       (or (null match) name)))))
;;     (kill-buffer buf)))

;; (defun edts_debug--update-bindings (bindings)
;;   (with-writable-buffer "*Edts_Debugger Bindings*"
;;    (erase-buffer)
;;    (insert "Current bindings in scope:\n\n")
;;    (mapcar #'(lambda (binding)
;;                (insert (format "%s = %s\n"
;;                                (car binding)
;;                                (cdr binding))))
;;            bindings)))

;; (defun edts_debug-handle-debugger-reply (reply)
;;   (let ((state (intern (cdr (assoc 'state reply)))))
;;     (case state
;;       ('break
;;        (let ((file (cdr (assoc 'file reply)))
;;              (module (cdr (assoc 'module reply)))
;;              (line (cdr (assoc 'line reply)))
;;              (bindings (cdr (assoc 'var_bindings reply))))
;;          (edts-log-info "Break at %s:%s" module line)
;;          (edts_debug-enter-debug-mode file line)
;;          (edts_debug--update-bindings bindings)))
;;       ('idle
;;        (edts-face-remove-overlays '("edts_debug-current-line"))
;;        (edts-log-info "Finished."))
;;       ('error
;;        (edts-log-info "Error:%s" (cdr (assoc 'message reply)))))))

;; (defun edts_debug-update-breakpoints ()
;;   "Display breakpoints in the buffer"
;;   (edts-face-remove-overlays '("edts_debug-breakpoint"))
;;   (let ((breaks (edts-get-breakpoints (or (edts-node-name)
;;                                           (edts_debug-buffer-node-name)))))
;;     (dolist (b breaks)
;;       (let ((module (cdr (assoc 'module b)))
;;             (line (cdr (assoc 'line b)))
;;             (status (cdr (assoc 'status b))))
;;         (if (and (equal module (erlang-get-module))
;;                  (equal status "active"))
;;             (edts-face-display-overlay 'edts-face-breakpoint-enabled-line
;;                                        line "Breakpoint" "edts_debug-breakpoint"
;;                                        10 t))))))


;; (defun edts_debug-make-debug-buffer-name (&optional file-name)
;;   (format "*Edts_Debugger <%s>*" (edts-node-name)))

;; (defun edts_debug-buffer-node-name ()
;;   (save-match-data
;;     (let* ((name (buffer-name))
;;            (match (string-match "<\\([^)]+\\)>" name)))
;;       (match-string 1 name))))

;; (defun edts_debug--match-buffers (predicate)
;;   "Returns a list of buffers for which PREDICATE does not evaluate to T"
;;   (delq t
;;         (mapcar predicate (buffer-list))))

;; (defmacro with-writable-buffer (buffer-or-name &rest body)
;;   "Evaluates BODY by marking BUFFER-OR-NAME as writable and restoring its read-only status afterwards"
;;   `(with-current-buffer ,buffer-or-name
;;      (let ((was-read-only buffer-read-only))
;;        (setq buffer-read-only nil)
;;        ,@body
;;        (setq buffer-read-only was-read-only))))

(provide 'edts_debug)