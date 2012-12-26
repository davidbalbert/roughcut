(def VERSION "0.0.0")

(def defmacro (macro (name args body)
                     `(def ~name (macro ~args ~body))))

(defmacro defn (name args & expressions)
  `(def ~name ~(cons 'fn (cons args expressions))))

(defn list (& args) args)

(defmacro unless (condition yes no)
  `(if (not ~condition) ~yes ~no))

(defn reduce (f acc list)
      (if (first list)
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
