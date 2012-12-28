(def VERSION "0.0.0")

; We'll start with quote

(def quote (fn (list) list))

; Then defmacro

(def defmacro (macro (name args body)
                     `(def ~name (macro ~args ~body))))

; Defn needs cons, which we'll implement in terms of concat

(def concat (fn (& lists) (send lists :flatten 1)))
(def cons (fn (val list) (concat `(~val) list)))

; And finally defn! We're up and running

(defmacro defn (name args & expressions)
  `(def ~name ~(cons 'fn (cons args expressions))))


(defmacro let (bindings & expressions)
  (concat `(~(concat `(fn ~(filter-by-index even? bindings))
                     expressions))
          (filter-by-index odd? bindings)))

(defmacro do (& expressions)
  (concat '(let ()) expressions))


; List manipulation

(defn first (list) (send list :[] 0))
(defn rest (list)
      (or (send list :[] 1..-1)
          ()))

(defn list (& args) args)
(defn list? (obj) (send obj :is_a? (send Sexp)))
(defn empty? (list) (= list ()))

(defn eval (list) (send self :eval list))

; Mathy stuff

(defn + (& args) (send args :reduce :+))
(defn - (& args) (send args :reduce :-))
(defn * (& args) (send args :reduce :*))
(defn / (& args) (send args :reduce :/))
(defn mod (a b) (send a :% b))

(defn even? (n) (= 0 (mod n 2)))
(defn odd? (n) (= 1 (mod n 2)))


; Boolean logic

(defn = (a b) (send a :== b))
(defn not (a) (send a :!))
(defn < (a b) (send a :< b))
(defn <= (a b) (send a :<= b))
(defn > (a b) (send a :> b))
(defn >= (a b) (send a :>= b))

(defmacro or (condition & args)
  (if (empty? args)
    `(if ~condition
       ~condition
       false)
    `(if ~condition
       ~condition
       ~(concat '(or) args))))

; Control flow
; TODO: add cond here

(defmacro unless (condition yes no)
  `(if (not ~condition) ~yes ~no))


; Higher order stuff

(defn reduce (f acc list)
      (unless (empty? list)
        (reduce f (f acc (first list)) (rest list))
        acc))

(defn reverse (list)
      (reduce (fn (acc el) (cons el acc))
              ()
              list))

(defn map (f list)
      (reduce (fn (acc el) (cons (f el) acc))
              ()
              (reverse list)))

(defn filter (pred list)
      (reduce (fn (acc el)
                  (if (pred el)
                    (cons el acc)
                    acc))
              ()
              (reverse list)))

(defn reduce-with-index (f acc list)
      (reduce-with-index-helper f acc list 0))

(defn reduce-with-index-helper (f acc list index)
      (unless (empty? list)
        (reduce-with-index-helper
          f
          (f acc (first list) index)
          (rest list)
          (+ index 1))
        acc))

(defn filter-by-index (pred list)
      (reverse (reduce-with-index (fn (acc el idx)
                                      (if (pred idx)
                                        (cons el acc)
                                        acc))
                                  ()
                                  list)))

; Macros

(defn macroexpand (form)
      (macroexpand-helper (macroexpand-1 form) form))

(defn macroexpand-helper (new old)
      (if (= new old)
        new
        (macroexpand-helper (macroexpand-1 new) new)))

(defn macroexpand-all (form)
      (if (list? (macroexpand form))
        (map macroexpand (macroexpand form))
        form))
