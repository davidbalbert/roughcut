(def VERSION "0.0.0")

"Note: this line and everything after are thrown out because we don't parse multiple expressions correctly"
"Also note, we don't have comments, so we'll just eval these strings ;)"
(def FOO 123)

(def reduce (fn (f acc list)
                (if (first list)
                  (reduce f (f acc (first list)) (rest list))
                  acc)))

