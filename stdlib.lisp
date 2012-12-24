(def VERSION "0.0.0")

(def reduce (fn (f acc list)
                (if (first list)
                  (reduce f (f acc (first list)) (rest list))
                  acc)))

(def reverse (fn (list)
                 (reduce (fn (acc el) (cons el acc))
                         (quote ())
                         list)))

(def map (fn (f list)
             (reduce (fn (acc el) (cons (f el) acc))
                     (quote ())
                     (reverse list))))

(def filter (fn (pred list)
                (reduce (fn (acc el)
                            (if (pred el)
                              (cons el acc)
                              acc))
                        (quote ())
                        (reverse list))))
