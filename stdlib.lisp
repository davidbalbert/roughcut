(def VERSION "0.0.0")

(def macroexpand (fn (form)
                     (macroexpand-helper (macroexpand-1 form) form)))

(def macroexpand-helper (fn (new old)
                            (if (= new old)
                              new
                              (macroexpand-helper (macroexpand-1 new) new))))

(def unless (macro (condition yes no)
                   `(if (not ~condition) ~yes ~no)))

(def reduce (fn (f acc list)
                (if (first list)
                  (reduce f (f acc (first list)) (rest list))
                  acc)))

(def reverse (fn (list)
                 (reduce (fn (acc el) (cons el acc))
                         ()
                         list)))

(def map (fn (f list)
             (reduce (fn (acc el) (cons (f el) acc))
                     ()
                     (reverse list))))

(def filter (fn (pred list)
                (reduce (fn (acc el)
                            (if (pred el)
                              (cons el acc)
                              acc))
                        ()
                        (reverse list))))
