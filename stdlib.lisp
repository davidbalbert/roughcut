(def VERSION "0.0.0")

; We'll start with defmacro

(def defmacro (macro (name args body)
                     `(def ~name (macro ~args ~body))))

; And now we'll use that to make defn!

(defmacro defn (name args & expressions)
  `(def ~name (fn ~args ~@expressions)))

(defmacro let (bindings & expressions)
  `((fn ~(filter-by-index even? bindings)
        ~@expressions) ~@(filter-by-index odd? bindings)))

(defmacro let* (bindings & expressions)
  (if (>= 2 (size bindings))
    `(let ~bindings ~@expressions)

    `((fn (~(first bindings))
          (let* ~(rest (rest bindings)) ~@expressions))
      ~(second bindings))))

(defmacro letrec (bindings & expressions)
  (let* (names (filter-by-index even? bindings)
         values (filter-by-index odd? bindings)
         nil-bindings
           (mapcat (fn (el) (list el nil)) names)
         binding-pairs
           (zip2 names values)
         set!s
           (map (fn (pair) (cons 'set! pair)) binding-pairs))
    `(let ~nil-bindings ~@set!s ~@expressions)))


(defmacro do (& expressions)
  `(let () ~@expressions))

(defn identity (x) x)

; List manipulation

(defn rest (list)
      (send list :rest))

(defn first (list) (send list :first))
(defn second (list) (first (rest list)))

(defn cons (val list) `(~val ~@list))

(defn concat (& lists)
      (let (concat2
            (fn (a b)
                (reduce (fn (acc el) (cons el acc))
                        b
                        (reverse a)))
            reversed-lists
            (reverse lists))
        (reduce (fn (a b) (concat2 b a))
                (first reversed-lists)
                (rest reversed-lists))))

(defn list (& args) args)
(defn list? (obj) (or (= (type obj) (send List))
                      (= (type obj) (send EmptyList))))

(defn empty? (list) (= list ()))
(defn size (list) (reduce (fn (acc el) (+ acc 1)) 0 list))
(defn take (num list)
      (letrec (take-helper
             (fn (num list new-list)
                 (if (zero? num)
                   new-list
                   (take-helper
                     (- num 1)
                     (rest list)
                     (cons (first list) new-list)))))
        (reverse (take-helper num list ()))))

(defn zip2 (l1 l2)
      (if (or (empty? l1) (empty? l2))
        ()
        (cons (list (first l1) (first l2))
              (zip2 (rest l1) (rest l2)))))

(defn eval (list) (send self :eval list))

(defn choose (list k)
      (cond (= k 0) '(())
            (> k (size list)) ()
            :else (concat
                    (map (fn (combo) (cons (first list) combo))
                         (choose (rest list) (- k 1)))
                    (choose (rest list) k))))


; Introspection

(defn type (o) (send o :class))

; Strings

(defn match (str pattern) (send str :match pattern))

; Hashes

(defn keys (hash) (send hash :keys))
(defn values (hash) (send hash :values))

; Mathy stuff

(defn + (& args) (send args :reduce :+))
(defn - (& args) (send args :reduce :-))
(defn * (& args) (send args :reduce :*))
(defn / (& args) (send args :reduce :/))
(defn mod (a b) (send a :% b))

(defn even? (n) (= 0 (mod n 2)))
(defn odd? (n) (= 1 (mod n 2)))
(defn zero? (n) (= 0 n))

; Boolean logic

(defn = (a b) (send a :== b))
(defn not (a) (send a :!))
(defn < (a b) (send a :< b))
(defn <= (a b) (send a :<= b))
(defn > (a b) (send a :> b))
(defn >= (a b) (send a :>= b))

(defmacro or (condition & args)
  (if (empty? args)
    `(if ~condition ~condition false)
    `(if ~condition ~condition (or ~@args))))

(defmacro and (condition & args)
  (if (empty? args)
    `(if ~condition ~condition false)
    `(if ~condition (and ~@args) false)))

; Control flow

(defmacro unless (condition & branches)
  `(if (not ~condition) ~@branches))

(defmacro cond (& clauses)
  (if (= 0 (size clauses))
    nil
    (if (= (first clauses) :else)
      (second clauses)
      `(if ~(first clauses)
         ~(second clauses)
         (cond ~@(rest (rest clauses)))))))

(defn exit () (send self :raise (send Exit)))

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
      (reverse (reduce (fn (acc el) (cons (f el) acc))
                       ()
                       list)))

(defn mapcat (f list)
      (apply concat (map f list)))

(defn filter (pred list)
      (reverse (reduce (fn (acc el)
                           (if (pred el)
                             (cons el acc)
                             acc))
                       ()
                       list)))

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

(defn macroexpand-1 (form)
      (send self :macroexpand_1 form))

(defn macroexpand (form)
      (macroexpand-helper (macroexpand-1 form) form))

(defn macroexpand-helper (new old)
      (if (= new old)
        new
        (macroexpand-helper (macroexpand-1 new) new)))

(defn macroexpand-all (form)
      (if (list? (macroexpand form))
        (map macroexpand-all (macroexpand form))
        (macroexpand form)))
