(def VERSION "0.0.0")

(def reduce (fn (f acc list)
                (if (first list)
                  (reduce f (f acc (first list)) (rest list))
                  acc)))

