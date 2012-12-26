(def VERSION "0.0.0")

(def defmacro (macro (name args body)
                     `(def ~name (macro ~args ~body))))

(defmacro defn (name args & expressions)
  `(def ~name ~(cons 'fn (cons args expressions))))

(defn even? (n) (= 0 (mod n 2)))
(defn odd? (n) (= 1 (mod n 2)))

(defmacro let (bindings & expressions)
  (concat `(~(concat `(fn ~(filter-by-index even? bindings))
                     expressions))
          (filter-by-index odd? bindings)))

(defn list (& args) args)

(defmacro unless (condition yes no)
  `(if (not ~condition) ~yes ~no))

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
