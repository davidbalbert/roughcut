(def VERSION "0.0.0")

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
