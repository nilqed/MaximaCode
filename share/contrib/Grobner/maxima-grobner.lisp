;;; -*-  Mode: Lisp; Package: Maxima; Syntax: Common-Lisp; Base: 10 -*- 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                              
;;;  $Id: maxima-grobner.lisp,v 1.3 2005-11-07 17:37:10 rtoy Exp $		 
;;;  Copyright (C) 1999, 2002 Marek Rychlik <rychlik@u.arizona.edu>		 
;;;  		       								 
;;;  This program is free software; you can redistribute it and/or modify	 
;;;  it under the terms of the GNU General Public License as published by	 
;;;  the Free Software Foundation; either version 2 of the License, or		 
;;;  (at your option) any later version.					 
;;; 		       								 
;;;  This program is distributed in the hope that it will be useful,		 
;;;  but WITHOUT ANY WARRANTY; without even the implied warranty of		 
;;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the		 
;;;  GNU General Public License for more details.				 
;;; 		       								 
;;;  You should have received a copy of the GNU General Public License		 
;;;  along with this program; if not, write to the Free Software 		 
;;;  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.	 
;;;										 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package :maxima)
(macsyma-module cgb-maxima)

(eval-when (load eval)
  (format t "~&Loading maxima-grobner ~a ~a~%"
	  "$Revision: 1.3 $" "$Date: 2005-11-07 17:37:10 $"))

;;FUNCTS is loaded because it contains the definition of LCM
($load "functs")

;; Macros for making lists with iterators - an exammple of GENSYM
;; MAKELIST-1 makes a list with one iterator, while MAKELIST accepts an
;; arbitrary number of iterators

;; Sample usage:
;; Without a step:
;; >(makelist-1 (* 2 i) i 0 10)
;; (0 2 4 6 8 10 12 14 16 18 20)
;; With a step of 3:
;; >(makelist-1 (* 2 i) i 0 10 3)
;; (0 6 12 18)

;; Generate sums of squares of numbers between 1 and 4:
;; >(makelist (+ (* i i) (* j j)) (i 1 4) (j 1 i))
;; (2 5 8 10 13 18 17 20 25 32)
;; >(makelist (list i j '---> (+ (* i i) (* j j))) (i 1 4) (j 1 i))
;; ((1 1 ---> 2) (2 1 ---> 5) (2 2 ---> 8) (3 1 ---> 10) (3 2 ---> 13)
;; (3 3 ---> 18) (4 1 ---> 17) (4 2 ---> 20) (4 3 ---> 25) (4 4 ---> 32))

;; Evaluate expression expr with variable set to lo, lo+1,... ,hi
;; and put the results in a list.
(defmacro makelist-1 (expr var lo hi &optional (step 1))
  (let ((l (gensym)))
    `(do ((,var ,lo (+ ,var ,step))
	  (,l nil (cons ,expr ,l)))
	 ((> ,var ,hi) (reverse ,l))
       (declare (fixnum ,var)))))

(defmacro makelist (expr (var lo hi &optional (step 1)) &rest more)
  (if (endp more)
      `(makelist-1 ,expr ,var ,lo ,hi ,step)
    (let* ((l (gensym)))
      `(do ((,var ,lo (+ ,var ,step))
	    (,l nil (nconc ,l `,(makelist ,expr ,@more))))
	   ((> ,var ,hi) ,l)
	 (declare (fixnum ,var))))))

;;----------------------------------------------------------------
;; This package implements BASIC OPERATIONS ON MONOMIALS
;;----------------------------------------------------------------
;; DATA STRUCTURES: Monomials are represented as lists:
;;
;; 	monom:	(n1 n2 ... nk) where ni are non-negative integers
;;
;; However, lists may be implemented as other sequence types,
;; so the flexibility to change the representation should be
;; maintained in the code to use general operations on sequences
;; whenever possible. The optimization for the actual representation
;; should be left to declarations and the compiler.
;;----------------------------------------------------------------
;; EXAMPLES: Suppose that variables are x and y. Then
;;
;; 	Monom x*y^2 ---> (1 2)
;;
;;----------------------------------------------------------------

(deftype exponent ()
  "Type of exponent in a monomial."
  'fixnum)

(deftype monom (&optional dim)
  "Type of monomial."
  `(simple-array exponent (,dim)))

(declaim (optimize (speed 3) (safety 0)))

(declaim (ftype (function (monom) fixnum) monom-dimension monom-sugar)
	 (ftype (function (monom &optional fixnum fixnum) fixnum) monom-total-degree)
	 (ftype (function (monom monom) monom) monom-div monom-mul monom-lcm monom-gcd)
	 (ftype (function (monom monom) (member t nil)) monom-divides-p monom-divisible-by-p monom-rel-prime-p)
	 (ftype (function (monom monom monom) (member t nil)) monom-divides-monom-lcm-p)
	 (ftype (function (monom monom monom monom) (member t nil)) monom-lcm-divides-monom-lcm-p)
	 (ftype (function (monom fixnum) (member t nil)) monom-depends-p)
	 ;;(ftype (function (t monom &optional monom) monom) monom-map)
	 ;;(ftype (function (monom monom) monom) monom-append)
	 )

(declaim (inline monom-mul monom-div
		 monom-total-degree monom-divides-p
		 monom-divisible-by-p monom-rel-prime monom-lcm))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Construction of monomials
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmacro make-monom (dim &key (initial-contents nil initial-contents-supplied-p)
			       (initial-element 0 initial-element-supplied-p))
  "Make a monomial with DIM variables. Additional argument
INITIAL-CONTENTS specifies the list of powers of the consecutive
variables. The alternative additional argument INITIAL-ELEMENT
specifies the common power for all variables."
  (declare (fixnum dim))
  `(make-array ,dim
	       :element-type 'exponent
	       ,@(when initial-contents-supplied-p `(:initial-contents ,initial-contents))
	       ,@(when initial-element-supplied-p `(:initial-element ,initial-element))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Operations on monomials
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmacro monom-elt (m index)
  "Return the power in the monomial M of variable number INDEX."
  `(elt ,m ,index))

(defun monom-dimension (m)
  "Return the number of variables in the monomial M."
  (length m))

(defun monom-total-degree (m &optional (start 0) (end (length m)))
  "Return the todal degree of a monomoal M. Optinally, a range
of variables may be specified with arguments START and END."
  (declare (type monom m) (fixnum start end))
  (reduce #'+ m :start start :end end))

(defun monom-sugar (m &aux (start 0) (end (length m)))
  "Return the sugar of a monomial M. Optinally, a range
of variables may be specified with arguments START and END."
  (declare (type monom m) (fixnum start end))
  (monom-total-degree m start end))

(defun monom-div (m1 m2 &aux (result (copy-seq m1)))
  "Divide monomial M1 by monomial M2."
  (declare (type monom m1 m2 result))
  (map-into result #'- m1 m2))

(defun monom-mul (m1 m2  &aux (result (copy-seq m1)))
  "Multiply monomial M1 by monomial M2."
  (declare (type monom m1 m2 result))
  (map-into result #'+ m1 m2))

(defun monom-divides-p (m1 m2)
  "Returns T if monomial M1 divides monomial M2, NIL otherwise."
  (declare (type monom m1 m2))
  (every #'<= m1 m2))

(defun monom-divides-monom-lcm-p (m1 m2 m3)
  "Returns T if monomial M1 divides MONOM-LCM(M2,M3), NIL otherwise."
  (declare (type monom m1 m2 m3))
  (every #'(lambda (x y z) (declare (type exponent x y z)) (<= x (max y z))) m1 m2 m3))

(defun monom-lcm-divides-monom-lcm-p (m1 m2 m3 m4)
  "Returns T if monomial MONOM-LCM(M1,M2) divides MONOM-LCM(M3,M4), NIL otherwise."
  (declare (type monom m1 m2 m3 m4))
  (every #'(lambda (x y z w) (declare (type exponent x y z w)) (<= (max x y) (max z w))) m1 m2 m3 m4))

(defun monom-lcm-equal-monom-lcm-p (m1 m2 m3 m4)
  "Returns T if monomial MONOM-LCM(M1,M2) equals MONOM-LCM(M3,M4), NIL otherwise."
  (declare (type monom m1 m2 m3 m4))
  (every #'(lambda (x y z w) (declare (type exponent x y z w)) (= (max x y) (max z w))) m1 m2 m3 m4))

(defun monom-divisible-by-p (m1 m2)
  "Returns T if monomial M1 is divisible by monomial M2, NIL otherwise."
  (declare (type monom m1 m2))
   (every #'>= m1 m2))

(defun monom-rel-prime-p (m1 m2)
  "Returns T if two monomials M1 and M2 are relatively prime (disjoint)."
  (declare (type monom m1 m2))
  (every #'(lambda (x y) (declare (type exponent x y)) (zerop (min x y))) m1 m2))

(defun monom-equal-p (m1 m2)
  "Returns T if two monomials M1 and M2 are equal."
  (declare (type monom m1 m2))
  (every #'= m1 m2))

(defun monom-lcm (m1 m2 &aux (result (copy-seq m1)))
  "Returns least common multiple of monomials M1 and M2."
  (declare (type monom m1 m2))
  (map-into result #'max m1 m2))

(defun monom-gcd (m1 m2 &aux (result (copy-seq m1)))
  "Returns greatest common divisor of monomials M1 and M2."
  (declare (type monom m1 m2))
  (map-into result #'min m1 m2))

(defun monom-depends-p (m k)
  "Return T if the monomial M depends on variable number K."
  (declare (type monom m) (fixnum k))
  (plusp (elt m k)))

(defmacro monom-map (fun m &rest ml &aux (result `(copy-seq ,m)))
  `(map-into ,result ,fun ,m ,@ml))

(defmacro monom-append (m1 m2)
  `(concatenate 'monom ,m1 ,m2))

(defmacro monom-contract (k m)
  `(subseq ,m ,k))

(defun monom-exponents (m)
  (declare (type monom m))
  (coerce m 'list))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Implementations of various admissible monomial orders
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; pure lexicographic
(defun lex> (p q &optional (start 0) (end (monom-dimension  p)))
  "Return T if P>Q with respect to lexicographic order, otherwise NIL.
The second returned value is T if P=Q, otherwise it is NIL."
  (declare (type monom p q) (type fixnum start end))
  (do ((i start (1+ i)))
      ((>= i end) (values NIL T))
    (declare (type fixnum i))
    (cond
     ((> (monom-elt p i) (monom-elt q i))
      (return-from lex> (values t nil)))
     ((< (monom-elt p i) (monom-elt q i))
      (return-from lex> (values nil nil))))))

;; total degree order , ties broken by lexicographic
(defun grlex> (p q &optional (start 0) (end (monom-dimension  p)))
  "Return T if P>Q with respect to graded lexicographic order, otherwise NIL.
The second returned value is T if P=Q, otherwise it is NIL."
  (declare (type monom p q) (type fixnum start end))
  (let ((d1 (monom-total-degree p start end))
	(d2 (monom-total-degree q start end)))
    (cond
      ((> d1 d2) (values t nil))
      ((< d1 d2) (values nil nil))
      (t
	(lex> p q start end)))))


;; total degree, ties broken by reverse lexicographic
(defun grevlex> (p q &optional (start 0) (end (monom-dimension  p)))
  "Return T if P>Q with respect to graded reverse lexicographic order,
NIL otherwise. The second returned value is T if P=Q, otherwise it is NIL."
  (declare (type monom p q) (type fixnum start end))
  (let ((d1 (monom-total-degree p start end))
	(d2 (monom-total-degree q start end)))
    (cond
     ((> d1 d2) (values t nil))
     ((< d1 d2) (values nil nil))
     (t
      (revlex> p q start end)))))


;; reverse lexicographic
(defun revlex> (p q &optional (start 0) (end (monom-dimension  p)))
  "Return T if P>Q with respect to reverse lexicographic order, NIL
otherwise.  The second returned value is T if P=Q, otherwise it is
NIL. This is not and admissible monomial order because some sets do
not have a minimal element. This order is useful in constructing other
orders."
  (declare (type monom p q) (type fixnum start end))
  (do ((i (1- end) (1- i)))
      ((< i start) (values NIL T))
    (declare (type fixnum i))
    (cond
     ((< (monom-elt p i) (monom-elt q i))
      (return-from revlex> (values t nil)))
     ((> (monom-elt p i) (monom-elt q i))
      (return-from revlex> (values nil nil))))))


(defun invlex> (p q &optional (start 0) (end (monom-dimension  p)))
  "Return T if P>Q with respect to inverse lexicographic order, NIL otherwise
The second returned value is T if P=Q, otherwise it is NIL."
  (declare (type monom p q) (type fixnum start end))
  (do ((i (1- end) (1- i)))
	((< i start) (values NIL T))
    (declare (type fixnum i))
      (cond
	 ((> (monom-elt p i) (monom-elt q i))
	  (return-from invlex> (values t nil)))
	 ((< (monom-elt p i) (monom-elt q i))
	  (return-from invlex> (values nil nil))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Order making functions
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(declaim (type function *monomial-order* *primary-elimination-order* *secondary-elimination-order*))

(defvar *monomial-order* #'lex>
  "Default order for monomial comparisons")

(defmacro monomial-order (x y)
  `(funcall *monomial-order* ,x ,y))

(defun reverse-monomial-order (x y)
  (monomial-order y x))

(defvar *primary-elimination-order* #'lex>)

(defvar *secondary-elimination-order* #'lex>)

(defvar *elimination-order* nil
  "Default elimination order used in elimination-based functions.
If not NIL, it is assumed to be a proper elimination order. If NIL,
we will construct an elimination order using the values of
*PRIMARY-ELIMINATION-ORDER* and *SECONDARY-ELIMINATION-ORDER*.")

(defun elimination-order (k)
  "Return a predicate which compares monomials according to the
K-th elimination order. Two variables *PRIMARY-ELIMINATION-ORDER*
and *SECONDARY-ELIMINATION-ORDER* control the behavior on the first K
and the remaining variables, respectively."
  (declare (type fixnum k))
  #'(lambda (p q &optional (start 0) (end (monom-dimension  p)))
      (declare (type monom p q) (type fixnum start end))
      (multiple-value-bind (primary equal)
	   (funcall *primary-elimination-order* p q start k)
	 (if equal
	     (funcall *secondary-elimination-order* p q k end)
	   (values primary nil)))))

(defun elimination-order-1 (p q &optional (start 0) (end (monom-dimension  p)))
  "Equivalent to the function returned by the call to (ELIMINATION-ORDER 1)."
  (declare (type monom p q) (type fixnum start end))
  (cond
   ((> (monom-elt p start) (monom-elt q start)) (values t nil))
   ((< (monom-elt p start) (monom-elt q start)) (values nil nil))
   (t (funcall *secondary-elimination-order* p q (1+ start) end))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Priority queue stuff
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(declaim (integer *priority-queue-allocation-size*))

(defparameter *priority-queue-allocation-size* 16)

(defun priority-queue-make-heap (&key (element-type 'fixnum))
  (make-array *priority-queue-allocation-size* :element-type element-type :fill-pointer 1
	      :adjustable t))

(defstruct (priority-queue (:constructor priority-queue-construct))
  (heap (priority-queue-make-heap))
  test)

(defun make-priority-queue (&key (element-type 'fixnum)
			    (test #'<=)
			    (element-key #'identity))
  (priority-queue-construct
   :heap (priority-queue-make-heap :element-type element-type)
   :test #'(lambda (x y) (funcall test (funcall element-key y) (funcall element-key x)))))
  
(defun priority-queue-insert (pq item)
  (priority-queue-heap-insert (priority-queue-heap pq) item (priority-queue-test pq)))

(defun priority-queue-remove (pq)
  (priority-queue-heap-remove (priority-queue-heap pq) (priority-queue-test pq)))

(defun priority-queue-empty-p (pq)
  (priority-queue-heap-empty-p (priority-queue-heap pq)))

(defun priority-queue-size (pq)
  (fill-pointer (priority-queue-heap pq)))

(defun priority-queue-upheap (a k
	       &optional
	       (test #'<=)
	       &aux  (v (aref a k)))
  (declare (fixnum k))
  (assert (< 0 k (fill-pointer a)))
  (loop
   (let ((parent (ash k -1)))
     (when (zerop parent) (return))
     (unless (funcall test (aref a parent) v)
       (return))
     (setf (aref a k) (aref a parent)
	   k parent)))
  (setf (aref a k) v)
  a)

    
(defun priority-queue-heap-insert (a item &optional (test #'<=))
  (vector-push-extend item a)
  (priority-queue-upheap a (1- (fill-pointer a)) test))

(defun priority-queue-downheap (a k
		 &optional
		 (test #'<=)
		 &aux  (v (aref a k)) (j 0) (n (fill-pointer a)))
  (declare (fixnum k n j))
  (loop
   (unless (<= k (ash n -1))
     (return))
   (setf j (ash k 1))
   (if (and (< j n) (not (funcall test (aref a (1+ j)) (aref a j))))
       (incf j))
   (when (funcall test (aref a j) v)
     (return))
   (setf (aref a k) (aref a j)
	 k j))
  (setf (aref a k) v)
  a)

(defun priority-queue-heap-remove (a &optional (test #'<=) &aux (v (aref a 1)))
  (when (<= (fill-pointer a) 1) (error "Empty queue."))
  (setf (aref a 1) (vector-pop a))
  (priority-queue-downheap a 1 test)
  (values v a))

(defun priority-queue-heap-empty-p (a)
  (<= (fill-pointer a) 1))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Global switches
;; (Can be used in Maxima just fine)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmvar $poly_monomial_order '$lex
  "This switch controls which monomial order is used in polynomial
and Grobner basis calculations. If not set, LEX will be used")

(defmvar $poly_coefficient_ring '$expression_ring
  "This switch indicates the coefficient ring of the polynomials
that will be used in grobner calculations. If not set, Maxima's
general expression ring will be used. This variable may be set
to RING_OF_INTEGERS if desired.")

(defmvar $poly_primary_elimination_order NIL
  "Name of the default order for eliminated variables in elimination-based functions.
If not set, LEX will be used.")

(defmvar $poly_secondary_elimination_order NIL
  "Name of the default order for kept variables in elimination-based functions.
If not set, LEX will be used.")

(defmvar $poly_elimination_order NIL
  "Name of the default elimination order used in elimination calculations.
If set, it overrides the settings in variables POLY_PRIMARY_ELIMINATION_ORDER
and SECONDARY_ELIMINATION_ORDER. The user must ensure that this is a true
elimination order valid for the number of eliminated variables.")

(defmvar $poly_return_term_list NIL
  "If set to T, all functions in this package will return each polynomial as a
list of terms in the current monomial order rather than a Maxima general expression.")

(defmvar $poly_grobner_debug nil
  "If set to TRUE, produce debugging and tracing output.")

(defmvar $poly_grobner_algorithm '$buchberger
  "The name of the algorithm used to find grobner bases.")

(defmvar $poly_top_reduction_only NIL
  "If not FALSE, use top reduction only whenever possible.
Top reduction means that division algorithm stops after the first reduction.")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Coefficient ring operations
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; These are ALL operations that are performed on the coefficients by
;; the package, and thus the coefficient ring can be changed by merely
;; redefining these operations.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defstruct (ring)
  (parse #'identity :type function)
  (unit #'identity :type function)
  (zerop #'identity :type function)
  (add #'identity :type function)
  (sub #'identity :type function)
  (uminus #'identity :type function)
  (mul #'identity :type function)
  (div #'identity :type function)
  (lcm #'identity :type function)
  (ezgcd #'identity :type function)
  (gcd #'identity :type function))

(declaim (type ring *RingOfIntegers* *FieldOfRationals*))

(defparameter *RingOfIntegers*
    (make-ring
     :parse #'identity
     :unit #'(lambda () 1)
     :zerop #'zerop
     :add #'+
     :sub #'-
     :uminus #'-
     :mul #'*
     :div #'/
     :lcm #'lcm
     :ezgcd #'(lambda (x y &aux (c (gcd x y))) (values c (/ x c) (/ y c)))
     :gcd #'gcd)
  "The ring of integers.")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This is how we perform operations on coefficients
;; using Maxima functions. 
;;
;; Functions and macros dealing with internal representation structure
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defstruct (term
	    (:constructor make-term (monom coeff))
	    (:constructor make-term-variable)
	    ;;(:type list)
	    )
  (monom (make-monom 0) :type monom)
  (coeff nil))

(defun make-term-variable (ring nvars pos
				&optional
				(power 1)
				(coeff (funcall (ring-unit ring)))
				&aux
				(monom (make-monom nvars :initial-element 0)))
  (declare (fixnum nvars pos power))
  (incf (monom-elt monom pos) power)
  (make-term monom coeff))

(defun term-sugar (term)
  (monom-sugar (term-monom term)))

(defun termlist-sugar (p &aux (sugar -1))
  (declare (fixnum sugar))
  (dolist (term p sugar)
    (setf sugar (max sugar (term-sugar term)))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Low-level polynomial arithmetic done on 
;; lists of terms
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmacro termlist-lt (p) `(car ,p))
(defun termlist-lm (p) (term-monom (termlist-lt p)))
(defun termlist-lc (p) (term-coeff (termlist-lt p)))

(define-modify-macro scalar-mul (c) coeff-mul)

(declaim (ftype (function (ring t t) t) scalar-times-termlist))

(defun scalar-times-termlist (ring c p)
  "Multiply scalar C by a polynomial P. This function works
even if there are divisors of 0."
  (mapcan
   #'(lambda (term)
       (let ((c1 (funcall (ring-mul ring) c (term-coeff term))))
	 (unless (funcall (ring-zerop ring) c1)
	   (list (make-term (term-monom term) c1)))))
   p))


(declaim (ftype (function (ring term term) list) term-mul))

(defun term-mul (ring term1 term2)
  "Returns (LIST TERM) wheter TERM is the product of the terms TERM1 TERM2,
or NIL when the product is 0. This definition takes care of divisors of 0
in the coefficient ring."
  (let ((c (funcall (ring-mul ring) (term-coeff term1) (term-coeff term2))))
    (unless (funcall (ring-zerop ring) c)
      (list (make-term (monom-mul (term-monom term1) (term-monom term2)) c)))))

(declaim (ftype (function (ring term list) list) term-times-termlist))

(defun term-times-termlist (ring term f)
  (declare (type ring ring))
  (mapcan #'(lambda (term-f) (term-mul ring term term-f)) f))

(declaim (ftype (function (ring list term) list) termlist-times-term))

(defun termlist-times-term (ring f term)
  (mapcan #'(lambda (term-f) (term-mul ring term-f term)) f))

(declaim (ftype (function (monom term) term) monom-times-term))

(defun monom-times-term (m term)
  (make-term (monom-mul m (term-monom term)) (term-coeff term)))

(declaim (ftype (function (monom list) list) monom-times-poly))

(defun monom-times-termlist (m f)
  (cond
   ((null f) nil)
   (t
    (mapcar #'(lambda (x) (monom-times-term m x)) f))))

(declaim (ftype (function (ring list) list) termlist-uminus))

(defun termlist-uminus (ring f)
  (mapcar #'(lambda (x)
	      (make-term (term-monom x) (funcall (ring-uminus ring) (term-coeff x))))
	  f))

(declaim (ftype (function (ring list list) list) termlist-add termlist-sub termlist-mul))

(defun termlist-add (ring p q)
  (declare (type list p q))
  (do (r)
      ((cond
	((endp p)
	 (setf r (revappend r q)) t)
	((endp q)
	 (setf r (revappend r p)) t)
	(t
	 (multiple-value-bind
	     (lm-greater lm-equal)
	     (monomial-order (termlist-lm p) (termlist-lm q))
	   (cond
	    (lm-equal
	     (let ((s (funcall (ring-add ring) (termlist-lc p) (termlist-lc q))))
	       (unless (funcall (ring-zerop ring) s)	;check for cancellation
		 (setf r (cons (make-term (termlist-lm p) s) r)))
	       (setf p (cdr p) q (cdr q))))
	    (lm-greater
	     (setf r (cons (car p) r)
		   p (cdr p)))
	    (t (setf r (cons (car q) r)
		     q (cdr q)))))
	 nil))
       r)))

(defun termlist-sub (ring p q)
  (declare (type list p q))
  (do (r)
      ((cond
	((endp p)
	 (setf r (revappend r (termlist-uminus ring q)))
	 t)
	((endp q)
	 (setf r (revappend r p))
	 t)
	(t
	 (multiple-value-bind
	     (mgreater mequal)
	     (monomial-order (termlist-lm p) (termlist-lm q))
	   (cond
	    (mequal
	     (let ((s (funcall (ring-sub ring) (termlist-lc p) (termlist-lc q))))
	       (unless (funcall (ring-zerop ring) s)	;check for cancellation
		 (setf r (cons (make-term (termlist-lm p) s) r)))
	       (setf p (cdr p) q (cdr q))))
	    (mgreater
	     (setf r (cons (car p) r)
		   p (cdr p)))
	    (t (setf r (cons (make-term (termlist-lm q) (funcall (ring-uminus ring) (termlist-lc q))) r)
		     q (cdr q)))))
	 nil))
       r)))

;; Multiplication of polynomials
;; Non-destructive version
(defun termlist-mul (ring p q)
  (cond ((or (endp p) (endp q)) nil)	;p or q is 0 (represented by NIL)
	;; If p=p0+p1 and q=q0+q1 then pq=p0q0+p0q1+p1q
	((endp (cdr p))
	 (term-times-termlist ring (car p) q))
	((endp (cdr q))
	 (termlist-times-term ring p (car q)))
	(t
	 (let ((head (term-mul ring (termlist-lt p) (termlist-lt q)))
	       (tail (termlist-add ring (term-times-termlist ring (car p) (cdr q))
				   (termlist-mul ring (cdr p) q))))
	   (cond ((null head) tail)
		 ((null tail) head)
		 (t (nconc head tail)))))))
		    
(defun termlist-unit (ring dimension)
  (declare (fixnum dimension))
  (list (make-term (make-monom dimension :initial-element 0)
		   (funcall (ring-unit ring)))))

(defun termlist-expt (ring poly n &aux (dim (monom-dimension (termlist-lm poly))))
  (declare (type fixnum n dim))
  (cond
   ((minusp n) (error "termlist-expt: Negative exponent."))
   ((endp poly) (if (zerop n) (termlist-unit ring dim) nil))
   (t
    (do ((k 1 (ash k 1))
	 (q poly (termlist-mul ring q q))	;keep squaring
	 (p (termlist-unit ring dim) (if (not (zerop (logand k n))) (termlist-mul ring p q) p)))
	((> k n) p)
      (declare (fixnum k))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Additional structure operations on a list of terms
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun termlist-contract (p &optional (k 1))
  "Eliminate first K variables from a polynomial P."
  (mapcar #'(lambda (term) (make-term (monom-contract k (term-monom term))
				      (term-coeff term)))
	  p))

(defun termlist-extend (p &optional (m (list 0)))
  "Extend every monomial in a polynomial P by inserting at the
beginning of every monomial the list of powers M."
  (mapcar #'(lambda (term) (make-term (monom-append m (term-monom term))
				      (term-coeff term)))
	  p))

(defun termlist-add-variables (p n)
  "Add N variables to a polynomial P by inserting zero powers
at the beginning of each monomial."
  (declare (fixnum n))
  (mapcar #'(lambda (term)
	      (make-term (monom-append (make-monom n :initial-element 0)
				       (term-monom term))
			 (term-coeff term)))
	  p))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Arithmetic on polynomials
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defstruct (poly
	    ;;BOA constructor, by default constructs zero polynomial
	    (:constructor make-poly-from-termlist (termlist &optional (sugar (termlist-sugar termlist))))
	    (:constructor make-poly-zero (&aux (termlist nil) (sugar -1)))
	    ;;Constructor of polynomials representing a variable
	    (:constructor make-variable (ring nvars pos &optional (power 1)
					      &aux
					      (termlist (list
							 (make-term-variable ring nvars pos power)))
					      (sugar power)))
	    (:constructor poly-unit (ring dimension
				     &aux
				     (termlist (termlist-unit ring dimension))
				     (sugar 0))))
  (termlist nil :type list)
  (sugar -1 :type fixnum))

;; Leading term
(defmacro poly-lt (p) `(car (poly-termlist ,p)))

;; Second term
(defmacro poly-second-lt (p) `(cadar (poly-termlist ,p)))

;; Leading monomial
(defun poly-lm (p) (term-monom (poly-lt p)))

;; Second monomial
(defun poly-second-lm (p) (term-monom (poly-second-lt p)))

;; Leading coefficient
(defun poly-lc (p) (term-coeff (poly-lt p)))

;; Second coefficient
(defun poly-second-lc (p) (term-coeff (poly-second-lt p)))

;; Testing for a zero polynomial
(defun poly-zerop (p) (null (poly-termlist p)))

;; The number of terms
(defun poly-length (p) (length (poly-termlist p)))

(declaim (ftype (function (ring t poly) poly) scalar-times-poly))

(defun scalar-times-poly (ring c p)
  (make-poly-from-termlist (scalar-times-termlist ring c (poly-termlist p)) (poly-sugar p)))
    
(declaim (ftype (function (monom poly) poly) monom-times-poly))

(defun monom-times-poly (m p)
  (make-poly-from-termlist (monom-times-termlist m (poly-termlist p)) (+ (poly-sugar p) (monom-sugar m))))

(declaim (ftype (function (ring term poly) poly) term-times-poly))

(defun term-times-poly (ring term p)
  (make-poly-from-termlist (term-times-termlist ring term (poly-termlist p)) (+ (poly-sugar p) (term-sugar term))))

(declaim (ftype (function (ring poly poly) poly) poly-add poly-sub poly-mul))

(defun poly-add (ring p q)
  (make-poly-from-termlist (termlist-add ring (poly-termlist p) (poly-termlist q)) (max (poly-sugar p) (poly-sugar q))))

(defun poly-sub (ring p q)
  (make-poly-from-termlist (termlist-sub ring (poly-termlist p) (poly-termlist q)) (max (poly-sugar p) (poly-sugar q))))

(declaim (ftype (function (ring poly) poly) poly-uminus))

(defun poly-uminus (ring p)
  (make-poly-from-termlist (termlist-uminus ring (poly-termlist p)) (poly-sugar p)))

(defun poly-mul (ring p q)
  (make-poly-from-termlist (termlist-mul ring (poly-termlist p) (poly-termlist q)) (+ (poly-sugar p) (poly-sugar q))))

(declaim (ftype (function (ring poly fixnum) poly) poly-expt))

(defun poly-expt (ring p n)
  (make-poly-from-termlist (termlist-expt ring (poly-termlist p) n) (* n (poly-sugar p))))

(defun poly-append (&rest plist)
  (make-poly-from-termlist (apply #'append (mapcar #'poly-termlist plist))
	     (apply #'max (mapcar #'poly-sugar plist))))

(declaim (ftype (function (poly) poly) poly-nreverse))

(defun poly-nreverse (p)
  (setf (poly-termlist p) (nreverse (poly-termlist p)))
  p)

(declaim (ftype (function (poly &optional fixnum) poly) poly-contract))

(defun poly-contract (p &optional (k 1))
  (make-poly-from-termlist (termlist-contract (poly-termlist p) k)
	     (poly-sugar p)))

(declaim (ftype (function (poly &optional sequence)) poly-extend))

(defun poly-extend (p &optional (m (list 0)))
  (make-poly-from-termlist
   (termlist-extend (poly-termlist p) m)
   (+ (poly-sugar p) (monom-sugar m))))

(declaim (ftype (function (poly fixnum)) poly-add-variables))

(defun poly-add-variables (p k)
  (setf (poly-termlist p) (termlist-add-variables (poly-termlist p) k))
  p)

(defun poly-list-add-variables (plist k)
  (mapcar #'(lambda (p) (poly-add-variables p k)) plist))

(defun poly-standard-extension (plist &aux (k (length plist)))
  "Calculate [U1*P1,U2*P2,...,UK*PK], where PLIST=[P1,P2,...,PK]."
  (declare (list plist) (fixnum k))
  (labels ((incf-power (g i)
	     (dolist (x (poly-termlist g))
	       (incf (monom-elt (term-monom x) i)))
	     (incf (poly-sugar g))))
    (setf plist (poly-list-add-variables plist k))
    (dotimes (i k plist)
      (incf-power (nth i plist) i))))

(defun saturation-extension (ring F plist &aux (k (length plist)) (d (monom-dimension (poly-lm (car plist)))))
  "Calculate [F, U1*P1-1,U2*P2-1,...,UK*PK-1], where PLIST=[P1,P2,...,PK]."
  (setf F (poly-list-add-variables F k)
	plist (mapcar #'(lambda (x)
			  (setf (poly-termlist x) (nconc (poly-termlist x)
							 (list (make-term (make-monom d :initial-element 0)
									  (funcall (ring-uminus ring) (funcall (ring-unit ring)))))))
			  x)
		      (poly-standard-extension plist)))
  (append F plist))


(defun polysaturation-extension (ring F plist &aux (k (length plist))
						   (d (+ k (length (poly-lm (car plist))))))
  "Calculate [F, U1*P1+U2*P2+...+UK*PK-1], where PLIST=[P1,P2,...,PK]."
  (setf F (poly-list-add-variables F k)
	plist (apply #'poly-append (poly-standard-extension plist))
	(cdr (last (poly-termlist plist))) (list (make-term (make-monom d :initial-element 0)
							    (funcall (ring-uminus ring) (funcall (ring-unit ring))))))
  (append F (list plist)))

(defun saturation-extension-1 (ring F p) (polysaturation-extension ring F (list p)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Evaluation of polynomial (prefix) expressions
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun coerce-coeff (ring expr vars)
  "Coerce an element of the coefficient ring to a constant polynomial."
  ;; Modular arithmetic handler by rat
  (make-poly-from-termlist (list (make-term (make-monom (length vars) :initial-element 0)
			      (funcall (ring-parse ring) expr)))
	     0))

(defun poly-eval (ring expr vars &optional (list-marker '[))
  (labels ((p-eval (arg) (poly-eval ring arg vars))
	   (p-eval-list (args) (mapcar #'p-eval args))
	   (p-add (x y) (poly-add ring x y)))
    (cond
     ((eql expr 0) (make-poly-zero))
     ((member expr vars :test #'equalp)
      (let ((pos (position expr vars :test #'equalp)))
	(make-variable ring (length vars) pos)))
     ((atom expr)
      (coerce-coeff ring expr vars))
     ((eq (car expr) list-marker)
      (cons list-marker (p-eval-list (cdr expr))))
     (t
      (case (car expr)
	(+ (reduce #'p-add (p-eval-list (cdr expr))))
	(- (case (length expr)
	     (1 (make-poly-zero))
	     (2 (poly-uminus ring (p-eval (cadr expr))))
	     (3 (poly-sub ring (p-eval (cadr expr)) (p-eval (caddr expr))))
	     (otherwise (poly-sub ring (p-eval (cadr expr))
				  (reduce #'p-add (p-eval-list (cddr expr)))))))
	(*
	 (if (endp (cddr expr))		;unary
	     (p-eval (cdr expr))
	   (reduce #'(lambda (p q) (poly-mul ring p q)) (p-eval-list (cdr expr)))))
	(expt
	 (cond
	  ((member (cadr expr) vars :test #'equalp)
	   ;;Special handling of (expt var pow)
	   (let ((pos (position (cadr expr) vars :test #'equalp)))
	     (make-variable ring (length vars) pos (caddr expr))))
	  ((not (and (integerp (caddr expr)) (plusp (caddr expr))))
	   ;; Negative power means division in coefficient ring
	   ;; Non-integer power means non-polynomial coefficient
	   (coerce-coeff ring expr vars))
	  (t (poly-expt ring (p-eval (cadr expr)) (caddr expr)))))
	(otherwise
	 (coerce-coeff ring expr vars)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Global optimization/debugging options
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;All inline functions of this module
(declaim (inline free-of-vars make-pair-queue pair-queue-insert
		 pair-queue-remove pair-queue-empty-p
		 pair-queue-remove pair-queue-size Criterion-1
		 Criterion-2 grobner reduced-grobner sugar-pair-key
		 sugar-order normal-form normal-form-step grobner-op spoly
		 equal-test-p
		 ))

;;Optimization options
(declaim (optimize (speed 3) (safety 0)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Debugging/tracing
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



(defmacro debug-cgb (&rest args)
  `(when $poly_grobner_debug (format *terminal-io* ,@args)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; An implementation of Grobner basis
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun spoly (ring f g)
  "It yields the S-polynomial of polynomials F and G."
  (declare (type poly f g))
  (let* ((lcm (monom-lcm (poly-lm f) (poly-lm g)))
	  (mf (monom-div lcm (poly-lm f)))
	  (mg (monom-div lcm (poly-lm g))))
    (declare (type monom mf mg))
    (multiple-value-bind (c cf cg)
	(funcall (ring-ezgcd ring) (poly-lc f) (poly-lc g))
      (declare (ignore c))
      (poly-sub 
       ring
       (scalar-times-poly ring cg (monom-times-poly mf f))
       (scalar-times-poly ring cf (monom-times-poly mg g))))))


(defun poly-primitive-part (ring p)
  "Divide polynomial P with integer coefficients by gcd of its
coefficients and return the result."
  (declare (type poly p))
  (if (poly-zerop p)
      (values p 1)
    (let ((c (poly-content ring p)))
      (values (make-poly-from-termlist (mapcar
			  #'(lambda (x)
			      (make-term (term-monom x)
					 (funcall (ring-div ring) (term-coeff x) c)))
			  (poly-termlist p))
			 (poly-sugar p))
	       c))))

(defun poly-content (ring p)
  "Greatest common divisor of the coefficients of the polynomial P. Use the RING structure
to compute the greatest common divisor."
  (declare (type poly p))
  (reduce (ring-gcd ring) (mapcar #'term-coeff (rest (poly-termlist p))) :initial-value (poly-lc p)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; An implementation of the division algorithm
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(declaim (ftype (function (ring t t monom poly poly) poly) grobner-op))

(defun grobner-op (ring c1 c2 m f g)
  "Returns C2*F-C1*M*G, where F and G are polynomials M is a monomial.
Assume that the leading terms will cancel."
  #+grobner-check(funcall (ring-zerop ring)
			  (funcall (ring-sub ring)
				   (funcall (ring-mul ring) c2 (poly-lc f))
				   (funcall (ring-mul ring) c1 (poly-lc g))))
  #+grobner-check(monom-equal-p (poly-lm f) (monom-mul m (poly-lm g)))
  (poly-sub ring
	    (scalar-times-poly ring c2 f)
	    (scalar-times-poly ring c1 (monom-times-poly m g))))

(defun poly-pseudo-divide (ring f fl)
  "Pseudo-divide a polynomial F by the list of polynomials FL. Return
multiple values. The first value is a list of quotients A.  The second
value is the remainder R. The third argument is a scalar coefficient
C, such that C*F can be divided by FL within the ring of coefficients,
which is not necessarily a field. Finally, the fourth value is an
integer count of the number of reductions performed.  The resulting
objects satisfy the equation: C*F= sum A[i]*FL[i] + R."
  (declare (type poly f) (list fl))
  (do ((r (make-poly-zero))
       (c (funcall (ring-unit ring)))
       (a (make-list (length fl) :initial-element (make-poly-zero)))
       (division-count 0)
       (p f))
      ((poly-zerop p)
       (debug-cgb "~&~3T~d reduction~:p" division-count)
       (when (poly-zerop r) (debug-cgb " ---> 0"))
       (values (mapcar #'poly-nreverse a) (poly-nreverse r) c division-count))
    (declare (fixnum division-count))
    (do ((fl fl (rest fl))				;scan list of divisors
	 (b a (rest b)))
	((cond
	  ((endp fl)					;no division occurred
	   (push (poly-lt p) (poly-termlist r))		;move lt(p) to remainder
	   (setf (poly-sugar r) (max (poly-sugar r) (term-sugar (poly-lt p))))
	   (pop (poly-termlist p))			;remove lt(p) from p
	   t)
	  ((monom-divides-p (poly-lm (car fl)) (poly-lm p)) ;division occurred
	   (incf division-count)
	   (multiple-value-bind (gcd c1 c2)
	       (funcall (ring-ezgcd ring) (poly-lc (car fl)) (poly-lc p))
	     (declare (ignore gcd))
	     (let ((m (monom-div (poly-lm p) (poly-lm (car fl)))))
	       ;; Multiply the equation c*f=sum ai*fi+r+p by c1.
	       (mapl #'(lambda (x)
			 (setf (car x) (scalar-times-poly ring c1 (car x))))
		     a)
	       (setf r (scalar-times-poly ring c1 r)
		     c (funcall (ring-mul ring) c c1)
		     p (grobner-op ring c2 c1 m p (car fl)))
	       (push (make-term m c2) (poly-termlist (car b))))
	     t)))))))

(defun poly-exact-divide (ring f g)
  "Divide a polynomial F by another polynomial G. Assume that exact division
with no remainder is possible. Returns the quotient."
  (declare (type poly f g))
  (multiple-value-bind (quot rem coeff division-count)
      (poly-pseudo-divide ring f (list g))
    (declare (ignore division-count coeff)
	     (type poly quot rem) (type fixnum division-count))
    (unless (poly-zerop rem) (error "Exact division failed."))
    (car quot)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; An implementation of the normal form
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(declaim (ftype (function (ring t poly poly t fixnum)
			  (values poly poly t fixnum))
		normal-form-step))

(defun normal-form-step (ring fl p r c division-count
			 &aux (g (find (poly-lm p) fl
				       :test #'monom-divisible-by-p
				       :key #'poly-lm)))
  (cond
   (g					;division possible
    (incf division-count)
    (multiple-value-bind (gcd cg cp)
	(funcall (ring-ezgcd ring) (poly-lc g) (poly-lc p))
      (declare (ignore gcd))
      (let ((m (monom-div (poly-lm p) (poly-lm g))))
	;; Multiply the equation c*f=sum ai*fi+r+p by cg.
	(setf r (scalar-times-poly ring cg r)
	      c (funcall (ring-mul ring) c cg)
	      p (grobner-op ring cp cg m p g))))
    (debug-cgb "/"))
   (t							;no division possible
    (push (poly-lt p) (poly-termlist r))		;move lt(p) to remainder
    (setf (poly-sugar r) (max (poly-sugar r) (term-sugar (poly-lt p))))
    (pop (poly-termlist p))				;remove lt(p) from p
    (debug-cgb "+")))
  (values p r c division-count))

(declaim (ftype (function (ring poly t &optional t) (values poly t fixnum)) normal-form))

;; Merge it sometime with poly-pseudo-divide
(defun normal-form (ring f fl &optional (top-reduction-only $poly_top_reduction_only))
  ;; Loop invariant: c*f0=sum ai*fi+r+f, where f0 is the initial value of f
  #+grobner-check(when (null fl) (warn "normal-form: empty divisor list."))
  (do ((r (make-poly-zero))
       (c (funcall (ring-unit ring)))
       (division-count 0))
      ((or (poly-zerop f)
	   ;;(endp fl)
	   (and top-reduction-only (not (poly-zerop r))))
       (progn
	 (debug-cgb "~&~3T~d reduction~:p" division-count)
	 (when (poly-zerop r)
	   (debug-cgb " ---> 0")))
       (setf (poly-termlist f) (nreconc (poly-termlist r) (poly-termlist f)))
       (values f c division-count))
    (declare (fixnum division-count)
	     (type poly r))
    (multiple-value-setq (f r c division-count)
      (normal-form-step ring fl f r c division-count))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; These are provided mostly for debugging purposes To enable
;; verification of grobner bases with BUCHBERGER-CRITERION, do
;; (pushnew :grobner-check *features*) and compile/load this file.
;; With this feature, the calculations will slow down CONSIDERABLY.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun buchberger-criterion (ring G)
  "Returns T if G is a Grobner basis, by using the Buchberger
criterion: for every two polynomials h1 and h2 in G the S-polynomial
S(h1,h2) reduces to 0 modulo G."
  (every
   #'poly-zerop
   (makelist (normal-form ring (spoly ring (elt G i) (elt G j)) G nil)
	     (i 0 (- (length G) 2))
	     (j (1+ i) (1- (length G))))))

(defun grobner-test (ring G F)
  "Test whether G is a Grobner basis and F is contained in G. Return T
upon success and NIL otherwise."
  (debug-cgb "~&GROBNER CHECK: ")
  (let (($poly_grobner_debug nil)
	(stat1 (buchberger-criterion ring G))
	(stat2
	  (every #'poly-zerop
		 (makelist (normal-form ring (copy-tree (elt F i)) G nil)
			   (i 0 (1- (length F)))))))
    (unless stat1 (error "~&Buchberger criterion failed."))
    (unless stat2
      (error "~&Original polys not in ideal spanned by Grobner.")))
  (debug-cgb "~&GROBNER CHECK END")
  T)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Pair queue implementation
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun sugar-pair-key (p q &aux (lcm (monom-lcm (poly-lm p) (poly-lm q)))
				(d (monom-sugar lcm)))
  "Returns list (S LCM-TOTAL-DEGREE) where S is the sugar of the S-polynomial of
polynomials P and Q, and LCM-TOTAL-DEGREE is the degree of is LCM(LM(P),LM(Q))."
  (declare (type poly p q) (type monom lcm) (type fixnum d))
  (cons (max 
	 (+  (- d (monom-sugar (poly-lm p))) (poly-sugar p))
	 (+  (- d (monom-sugar (poly-lm q))) (poly-sugar q)))
	lcm))

(defstruct (pair
	    (:constructor make-pair (first second
					   &aux
					   (sugar (car (sugar-pair-key first second)))
					   (division-data nil))))
  (first nil :type poly)
  (second nil :type poly)
  (sugar 0 :type fixnum)
  (division-data nil :type list))
  
;;(defun pair-sugar (pair &aux (p (pair-first pair)) (q (pair-second pair)))
;;  (car (sugar-pair-key p q)))

(defun sugar-order (x y)
  "Pair order based on sugar, ties broken by normal strategy."
  (declare (type cons x y))
  (or (< (car x) (car y))
      (and (= (car x) (car y))
	   (< (monom-total-degree (cdr x))
	      (monom-total-degree (cdr y))))))

(defvar *pair-key-function* #'sugar-pair-key
  "Function that, given two polynomials as argument, computed the key
in the pair queue.")

(defvar *pair-order* #'sugar-order
  "Function that orders the keys of pairs.")

(defun make-pair-queue ()
  "Constructs a priority queue for critical pairs."
  (make-priority-queue
   :element-type 'pair
   :element-key #'(lambda (pair) (funcall *pair-key-function* (pair-first pair) (pair-second pair)))
   :test *pair-order*))

(defun pair-queue-initialize (pq F start
			      &aux
			      (s (1- (length F)))
			      (B (nconc (makelist (make-pair (elt F i) (elt F j))
						 (i 0 (1- start)) (j start s))
					(makelist (make-pair (elt F i) (elt F j))
						 (i start (1- s)) (j (1+ i) s)))))
  "Initializes the priority for critical pairs. F is the initial list of polynomials.
START is the first position beyond the elements which form a partial
grobner basis, i.e. satisfy the Buchberger criterion."
  (declare (type priority-queue pq) (type fixnum start))
  (dolist (pair B pq)
    (priority-queue-insert pq pair)))

(defun pair-queue-insert (B pair)
  (priority-queue-insert B pair))

(defun pair-queue-remove (B)
  (priority-queue-remove B))

(defun pair-queue-size (B)
  (priority-queue-size B))

(defun pair-queue-empty-p (B)
  (priority-queue-empty-p B))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Buchberger Algorithm Implementation
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun buchberger (ring F start &optional (top-reduction-only $poly_top_reduction_only)
		   &aux B B-done)
  "An implementation of the Buchberger algorithm. Return Grobner basis
of the ideal generated by the polynomial list F.  Polynomials 0 to
START-1 are assumed to be a Grobner basis already, so that certain
critical pairs will not be examined. If TOP-REDUCTION-ONLY set, top
reduction will be preformed. This function assumes that all polynomials
in F are non-zero."
  (declare (type fixnum start) (type priority-queue B) (type hash-table B-done))
  (when (endp F) (return-from buchberger F)) ;cut startup costs
  (debug-cgb "~&GROBNER BASIS - BUCHBERGER ALGORITHM")
  (when (plusp start) (debug-cgb "~&INCREMENTAL:~d done" start))
  #+grobner-check  (when (plusp start)
		     (grobner-test ring (subseq F 0 start) (subseq F 0 start)))
  ;;Initialize critical pairs
  (setf B (pair-queue-initialize (make-pair-queue)
				 F start)
	B-done (make-hash-table :test #'equal))
  (dotimes (i (1- start))
    (do ((j (1+ i) (1+ j))) ((>= j start))
      (setf (gethash (list (elt F i) (elt F j)) B-done) t)))
  (do ()
      ((pair-queue-empty-p B)
       #+grobner-check(grobner-test ring F F)
       (debug-cgb "~&GROBNER END")
       F)
    (let ((pair (pair-queue-remove B)))
      (declare (type pair pair))
      (cond
       ((Criterion-1 pair) nil)
       ((Criterion-2 pair B-done F) nil)
       (t 
	(let ((SP (normal-form ring
		   (spoly ring (pair-first pair) (pair-second pair))
		   F top-reduction-only)))
	  (declare (type poly SP))
	  (cond
	   ((poly-zerop SP)
	    nil)
	   (t
	    (setf SP (poly-primitive-part ring SP)
		  F (nconc F (list SP)))
	    ;; Add new critical pairs
	    (dolist (h F)
	      (pair-queue-insert B (make-pair h SP)))
	    (debug-cgb "~&Sugar: ~d Polynomials: ~d; Pairs left: ~d; Pairs done: ~d;"
		       (pair-sugar pair) (length F) (pair-queue-size B)
		       (hash-table-count B-done)))))))
      (setf (gethash (list (pair-first pair) (pair-second pair)) B-done) t))))

(defun parallel-buchberger (ring F start &optional (top-reduction-only $poly_top_reduction_only)
			    &aux B B-done)
  "An implementation of the Buchberger algorithm. Return Grobner basis
of the ideal generated by the polynomial list F.  Polynomials 0 to
START-1 are assumed to be a Grobner basis already, so that certain
critical pairs will not be examined. If TOP-REDUCTION-ONLY set, top
reduction will be preformed."
  (declare (ignore top-reduction-only)
	   (type fixnum start)
	   (type priority-queue B)
	   (type hash-table B-done))
  (when (endp F) (return-from parallel-buchberger F)) ;cut startup costs
  (debug-cgb "~&GROBNER BASIS - PARALLEL-BUCHBERGER ALGORITHM")
  (when (plusp start) (debug-cgb "~&INCREMENTAL:~d done" start))
  #+grobner-check  (when (plusp start)
		     (grobner-test ring (subseq F 0 start) (subseq F 0 start)))
  ;;Initialize critical pairs
  (setf B (pair-queue-initialize (make-pair-queue)
				 F start)
	B-done (make-hash-table :test #'equal))
  (dotimes (i (1- start))
    (do ((j (1+ i) (1+ j))) ((>= j start))
      (declare (type fixnum j))
      (setf (gethash (list (elt F i) (elt F j)) B-done) t)))
  (do ()
      ((pair-queue-empty-p B)
       #+grobner-check(grobner-test ring F F)
       (debug-cgb "~&GROBNER END")
       F)
    (let ((pair (pair-queue-remove B)))
      (when (null (pair-division-data pair))
	(setf (pair-division-data pair) (list (spoly ring
						     (pair-first pair)
						     (pair-second pair))
					      (make-poly-zero)
					      (funcall (ring-unit ring))
					      0)))
      (cond
       ((Criterion-1 pair) nil)
       ((Criterion-2 pair B-done F) nil)
       (t 
	(let* ((dd (pair-division-data pair))
	       (p (first dd))
	       (SP (second dd))
	       (c (third dd))
	       (division-count (fourth dd)))
	  (cond
	   ((poly-zerop p)		;normal form completed
	    (debug-cgb "~&~3T~d reduction~:p" division-count)
	    (cond 
	     ((poly-zerop SP)
	      (debug-cgb " ---> 0")
	      nil)
	     (t
	      (setf SP (poly-nreverse SP)
		    SP (poly-primitive-part ring SP)
		    F (nconc F (list SP)))
	      ;; Add new critical pairs
	      (dolist (h F)
		(pair-queue-insert B (make-pair h SP)))
	      (debug-cgb "~&Sugar: ~d Polynomials: ~d; Pairs left: ~d; Pairs done: ~d;"
			 (pair-sugar pair) (length F) (pair-queue-size B)
			 (hash-table-count B-done))))
	    (setf (gethash (list (pair-first pair) (pair-second pair)) B-done) t))
	   (t				;normal form not complete
	    (do ()
		((cond
		  ((> (poly-sugar SP) (pair-sugar pair))
		   (debug-cgb "(~a)?" (poly-sugar SP))
		   t)
		  ((poly-zerop p)
		   (debug-cgb ".")
		   t)
		  (t nil))
		 (setf (first dd) p
		       (second dd) SP
		       (third dd) c
		       (fourth dd) division-count
		       (pair-sugar pair) (poly-sugar SP))
		 (pair-queue-insert B pair))
	      (multiple-value-setq (p SP c division-count)
		(normal-form-step ring F p SP c division-count)))))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Grobner Criteria
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun Criterion-1 (pair &aux (f (pair-first pair)) (g (pair-second pair)))
  "Returns T if the leading monomials of the two polynomials
in G pointed to by the integers in PAIR have disjoint (relatively prime)
monomials. This test is known as the first Buchberger criterion."
  (declare (type pair pair))
  (when (monom-rel-prime-p (poly-lm f) (poly-lm g))
    (debug-cgb ":1")
    (return-from Criterion-1 t)))

(defun Criterion-2 (pair B-done partial-basis
		    &aux (f (pair-first pair)) (g (pair-second pair))
			 (place :before))
  "Returns T if the leading monomial of some element P of
PARTIAL-BASIS divides the LCM of the leading monomials of the two
polynomials in the polynomial list PARTIAL-BASIS, and P paired with
each of the polynomials pointed to by the the PAIR has already been
treated, as indicated by the absence in the hash table B-done."
  (declare (type pair pair) (type hash-table B-done)
	   (type poly f g))
  ;; In the code below we assume that pairs are ordered as follows: 
  ;; if PAIR is (I J) then I appears before J in the PARTIAL-BASIS.
  ;; We traverse the list PARTIAL-BASIS and keep track of where we
  ;; are, so that we can produce the pairs in the correct order
  ;; when we check whether they have been processed, i.e they
  ;; appear in the hash table B-done
  (dolist (h partial-basis nil)
    (cond
     ((eq h f)
      #+grobner-check(assert (eq place :before))
      (setf place :in-the-middle))
     ((eq h g)
      #+grobner-check(assert (eq place :in-the-middle))
      (setf place :after))
     ((and (monom-divides-monom-lcm-p (poly-lm h) (poly-lm f) (poly-lm g))
	   (gethash (case place
		      (:before (list h f))
		      ((:in-the-middle :after) (list f h)))
		    B-done)
	   (gethash (case place
		      ((:before :in-the-middle) (list h g))
		      (:after (list g h)))
		    B-done))
      (debug-cgb ":2")
      (return-from Criterion-2 t)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; An implementation of the algorithm of Gebauer and Moeller, as
;; described in the book of Becker-Weispfenning, p. 232
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun gebauer-moeller (ring F start &optional (top-reduction-only $poly_top_reduction_only)
			&aux B G F1)
  "Compute Grobner basis by using the algorithm of Gebauer and
Moeller.  This algorithm is described as BUCHBERGERNEW2 in the book by
Becker-Weispfenning entitled ``Grobner Bases''. This function assumes
that all polynomials in F are non-zero."
  (declare (ignore top-reduction-only)
	   (type fixnum start)
	   (type priority-queue B))
  (cond
   ((endp F) (return-from gebauer-moeller nil))
   ((endp (cdr F))
    (return-from gebauer-moeller (list (poly-primitive-part ring (car F))))))
   (debug-cgb "~&GROBNER BASIS - GEBAUER MOELLER ALGORITHM")
   (when (plusp start) (debug-cgb "~&INCREMENTAL:~d done" start))
  #+grobner-check  (when (plusp start)
		     (grobner-test ring (subseq F 0 start) (subseq F 0 start)))
  (setf B (make-pair-queue)
	G (subseq F 0 start)
	F1 (subseq F start))
  (do () ((endp F1))
    (multiple-value-setq (G B)
      (gebauer-moeller-update G B (poly-primitive-part ring (pop F1)))))
  (do () ((pair-queue-empty-p B))
    (let* ((pair (pair-queue-remove B))
	   (g1 (pair-first pair))
	   (g2 (pair-second pair))
	   (h (normal-form ring (spoly ring g1 g2)
			   G
			   nil #| Always fully reduce! |#
			   )))
      (unless (poly-zerop h)
	(setf h (poly-primitive-part ring h))
	(multiple-value-setq (G B)
	  (gebauer-moeller-update G B h))
	(debug-cgb "~&Sugar: ~d Polynomials: ~d; Pairs left: ~d~%"
		   (pair-sugar pair) (length G) (pair-queue-size B))
	)))
  #+grobner-check(grobner-test ring G F)
  (debug-cgb "~&GROBNER END")
  G)

(defun gebauer-moeller-update (G B h
		 &aux
		 C D E
		 (B-new (make-pair-queue))
		 G-new
		 pair)
  "An implementation of the auxillary UPDATE algorithm used by the
Gebauer-Moeller algorithm. G is a list of polynomials, B is a list of
critical pairs and H is a new polynomial which possibly will be added
to G. The naming conventions used are very close to the one used in
the book of Becker-Weispfenning."
  (declare
   #+allegro (dynamic-extent B)
   (type poly h)
   (type priority-queue B)
   (type pair pair))
  (setf C G D nil) 
  (do (g1) ((endp C))
    (declare (type poly g1))
    (setf g1 (pop C))
    (when (or (monom-rel-prime-p (poly-lm h) (poly-lm g1))
	      (and
	       (notany #'(lambda (g2) (monom-lcm-divides-monom-lcm-p
				       (poly-lm h) (poly-lm g2)
				       (poly-lm h) (poly-lm g1)))
		       C)
	       (notany #'(lambda (g2) (monom-lcm-divides-monom-lcm-p
				       (poly-lm h) (poly-lm g2)
				       (poly-lm h) (poly-lm g1)))
		       D)))
      (push g1 D)))
  (setf E nil)
  (do (g1) ((endp D))
    (declare (type poly g1))
    (setf g1 (pop D))
    (unless (monom-rel-prime-p (poly-lm h) (poly-lm g1))
      (push g1 E)))
  (do (g1 g2) ((pair-queue-empty-p B))
    (declare (type poly g1 g2))
    (setf pair (pair-queue-remove B)
	  g1 (pair-first pair)
	  g2 (pair-second pair))
    (when (or (not (monom-divides-monom-lcm-p
		    (poly-lm h)
		    (poly-lm g1) (poly-lm g2)))
	      (monom-lcm-equal-monom-lcm-p
	       (poly-lm g1) (poly-lm h)
	       (poly-lm g1) (poly-lm g2))
	      (monom-lcm-equal-monom-lcm-p
	       (poly-lm h) (poly-lm g2)
	       (poly-lm g1) (poly-lm g2)))
      (pair-queue-insert B-new (make-pair g1 g2))))
  (dolist (g3 E)
    (pair-queue-insert B-new (make-pair h g3)))
  (setf G-new nil)
  (do (g1) ((endp G))
    (declare (type poly g1))
    (setf g1 (pop G))
    (unless (monom-divides-p (poly-lm h) (poly-lm g1))
      (push g1 G-new)))
  (push h G-new)
  (values G-new B-new))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Standard postprocessing of Grobner bases
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun reduction (ring plist)
  "Reduce a list of polynomials PLIST, so that non of the terms in any of
the polynomials is divisible by a leading monomial of another
polynomial.  Return the reduced list."
  (do ((Q plist)
       (found t))
      ((not found)
       (mapcar #'(lambda (x) (poly-primitive-part ring x)) Q))
    ;;Find p in Q such that p is reducible mod Q\{p}
    (setf found nil)
    (dolist (x Q)
      (let ((Q1 (remove x Q)))
	(multiple-value-bind (h c div-count)
	    (normal-form ring x Q1 nil #| not a top reduction! |# )
	  (declare (ignore c))
	  (unless (zerop div-count)
	    (setf found t Q Q1)
	    (unless (poly-zerop h)
	      (setf Q (nconc Q1 (list h))))
	    (return)))))))

(defun minimization (P)
  "Returns a sublist of the polynomial list P spanning the same
monomial ideal as P but minimal, i.e. no leading monomial
of a polynomial in the sublist divides the leading monomial
of another polynomial."
  (do ((Q P)
       (found t))
      ((not found) Q)
    ;;Find p in Q such that lm(p) is in LM(Q\{p})
    (setf found nil
	  Q (dolist (x Q Q)
	      (let ((Q1 (remove x Q)))
		(when (member-if #'(lambda (p) (monom-divides-p (poly-lm x) (poly-lm p))) Q1)
		  (setf found t)
		  (return Q1)))))))

(defun poly-normalize (ring p &aux (c (poly-lc p)))
  "Divide a polynomial by its leading coefficient. It assumes
that the division is possible, which may not always be the
case in rings which are not fields. The exact division operator
is assumed to be provided by the RING structure of the
COEFFICIENT-RING package."
  (mapc #'(lambda (term)
	    (setf (term-coeff term) (funcall (ring-div ring) (term-coeff term) c)))
	(poly-termlist p))
  p)

(defun poly-normalize-list (ring plist)
  "Divide every polynomial in a list PLIST by its leading coefficient. "
  (mapcar #'(lambda (x) (poly-normalize ring x)) plist))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Algorithm and Pair heuristic selection
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun find-grobner-function (algorithm)
  "Return a function which calculates Grobner basis, based on its
names. Names currently used are either Lisp symbols, Maxima symbols or
keywords."
  (ecase algorithm
    ((buchberger :buchberger $buchberger) #'buchberger)
    ((parallel-buchberger :parallel-buchberger $parallel_buchberger) #'parallel-buchberger)
    ((gebauer-moeller :gebauer_moeller $gebauer_moeller) #'gebauer-moeller)))

(defun grobner (ring F &optional (start 0) (top-reduction-only nil))
  ;;(setf F (sort F #'< :key #'sugar))
  (funcall
   (find-grobner-function $poly_grobner_algorithm)
   ring F start top-reduction-only))

(defun reduced-grobner (ring F &optional (start 0) (top-reduction-only $poly_top_reduction_only))
  (reduction ring (grobner ring F start top-reduction-only)))

(defun set-pair-heuristic (method)
  "Sets up variables *PAIR-KEY-FUNCTION* and *PAIR-ORDER* used
to determine the priority of critical pairs in the priority queue."
  (ecase method
    ((sugar :sugar $sugar)
     (setf *pair-key-function* #'sugar-pair-key
	   *pair-order* #'sugar-order))
;     ((minimal-mock-spoly :minimal-mock-spoly $minimal_mock_spoly)
;      (setf *pair-key-function* #'mock-spoly
; 	   *pair-order* #'mock-spoly-order))
    ((minimal-lcm :minimal-lcm $minimal_lcm)
     (setf *pair-key-function* #'(lambda (p q)
				   (monom-lcm (poly-lm p) (poly-lm q)))
	   *pair-order* #'reverse-monomial-order))
    ((minimal-total-degree :minimal-total-degree $minimal_total_degree)
     (setf *pair-key-function* #'(lambda (p q)
				   (monom-total-degree
				    (monom-lcm (poly-lm p) (poly-lm q))))
	   *pair-order* #'<))
    ((minimal-length :minimal-length $minimal_length)
     (setf *pair-key-function* #'(lambda (p q)
				   (+ (poly-length p) (poly-length q)))
	   *pair-order* #'<))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Operations in ideal theory
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Does the term depend on variable K?
(defun term-depends-p (term k)
  "Return T if the term TERM depends on variable number K."
  (monom-depends-p (term-monom term) k))

;; Does the polynomial P depend on variable K?
(defun poly-depends-p (p k)
  "Return T if the term polynomial P depends on variable number K."
  (some #'(lambda (term) (term-depends-p term k)) (poly-termlist p)))

(defun ring-intersection (plist k)
  "This function assumes that polynomial list PLIST is a Grobner basis
and it calculates the intersection with the ring R[x[k+1],...,x[n]], i.e.
it discards polynomials which depend on variables x[0], x[1], ..., x[k]."
  (dotimes (i k plist)
    (setf plist
	  (remove-if #'(lambda (p)
			 (poly-depends-p p i))
		     plist))))

(defun elimination-ideal (ring flist k
			  &optional (top-reduction-only $poly_top_reduction_only) (start 0)
			  &aux (*monomial-order*
				(or *elimination-order*
				    (elimination-order k))))
  (ring-intersection (reduced-grobner ring flist start top-reduction-only) k))

(defun colon-ideal (ring F G &optional (top-reduction-only $poly_top_reduction_only))
  "Returns the reduced Grobner basis of the colon ideal Id(F):Id(G),
where F and G are two lists of polynomials. The colon ideal I:J is
defined as the set of polynomials H such that for all polynomials W in
J the polynomial W*H belongs to I."
  (cond
   ((endp G)
    ;;Id(G) consists of 0 only so W*0=0 belongs to Id(F)
    (if (every #'poly-zerop F)
	(error "First ideal must be non-zero.")
      (list (make-poly
	     (list (make-term
		    (make-monom (monom-dimension (poly-lm (find-if-not #'poly-zerop F)))
				:initial-element 0)
		    (funcall (ring-unit ring))))))))
   ((endp (cdr G))
    (colon-ideal-1 ring F (car G) top-reduction-only))
   (t
    (ideal-intersection ring
			(colon-ideal-1 ring F (car G) top-reduction-only)
			(colon-ideal ring F (rest G) top-reduction-only)
			top-reduction-only))))

(defun colon-ideal-1 (ring F g &optional (top-reduction-only $poly_top_reduction_only))
  "Returns the reduced Grobner basis of the colon ideal Id(F):Id({G}), where
F is a list of polynomials and G is a polynomial."
  (mapcar #'(lambda (x) (poly-exact-divide ring x g)) (ideal-intersection ring F (list g) top-reduction-only)))


(defun ideal-intersection (ring F G &optional (top-reduction-only $poly_top_reduction_only)
			   &aux (*monomial-order* (or *elimination-order*
						      #'elimination-order-1)))
  (mapcar #'poly-contract
	  (ring-intersection
	   (reduced-grobner
	    ring
	    (append (mapcar #'(lambda (p) (poly-extend p (list 1))) F)
		    (mapcar #'(lambda (p)
				(poly-append (poly-extend (poly-uminus ring p) (list 1))
					     (poly-extend p)))
			    G))
	    0
	    top-reduction-only)
	   1)))

(defun poly-lcm (ring f g)
  "Return LCM (least common multiple) of two polynomials F and G.
The polynomials must be ordered according to monomial order PRED
and their coefficients must be compatible with the RING structure
defined in the COEFFICIENT-RING package."
  (cond
    ((poly-zerop f) f)
    ((poly-zerop g) g)
    ((and (endp (cdr (poly-termlist f))) (endp (cdr (poly-termlist g))))
     (let ((m (monom-lcm (poly-lm f) (poly-lm g))))
       (make-poly-from-termlist (list (make-term m (funcall (ring-lcm ring) (poly-lc f) (poly-lc g)))))))
    (t
     (multiple-value-bind (f f-cont)
	 (poly-primitive-part ring f)
       (multiple-value-bind (g g-cont)
	   (poly-primitive-part ring g)
	 (scalar-times-poly
	  ring
	  (funcall (ring-lcm ring) f-cont g-cont)
	  (poly-primitive-part ring (car (ideal-intersection ring (list f) (list g) nil)))))))))

;; Do two Grobner bases yield the same ideal?
(defun grobner-equal (ring G1 G2)
  "Returns T if two lists of polynomials G1 and G2, assumed to be Grobner bases,
generate  the same ideal, and NIL otherwise."
  (and (grobner-subsetp ring G1 G2) (grobner-subsetp ring G2 G1)))

(defun grobner-subsetp (ring G1 G2)
  "Returns T if a list of polynomials G1 generates
an ideal contained in the ideal generated by a polynomial list G2,
both G1 and G2 assumed to be Grobner bases. Returns NIL otherwise."
  (every #'(lambda (p) (grobner-member ring p G2)) G1))

(defun grobner-member (ring p G)
  "Returns T if a polynomial P belongs to the ideal generated by the
polynomial list G, which is assumed to be a Grobner basis. Returns NIL otherwise."
  (poly-zerop (normal-form ring p G nil)))

;; Calculate F : p^inf
(defun ideal-saturation-1 (ring F p start &optional (top-reduction-only $poly_top_reduction_only)
			   &aux (*monomial-order* (or *elimination-order*
						      #'elimination-order-1)))
  "Returns the reduced Grobner basis of the saturation of the ideal
generated by a polynomial list F in the ideal generated by a single
polynomial P. The saturation ideal is defined as the set of
polynomials H such for some natural number n (* (EXPT P N) H) is in the ideal
F. Geometrically, over an algebraically closed field, this is the set
of polynomials in the ideal generated by F which do not identically
vanish on the variety of P."
  (mapcar
   #'poly-contract
   (ring-intersection
    (reduced-grobner
     ring
     (saturation-extension-1 ring F p)
     start top-reduction-only)
    1)))



;; Calculate F : p1^inf : p2^inf : ... : ps^inf
(defun ideal-polysaturation-1 (ring F plist start &optional (top-reduction-only $poly_top_reduction_only))
  "Returns the reduced Grobner basis of the ideal obtained by a
sequence of successive saturations in the polynomials
of the polynomial list PLIST of the ideal generated by the
polynomial list F."
  (cond
   ((endp plist) (reduced-grobner ring F start top-reduction-only))
   (t (let ((G (ideal-saturation-1 ring F (car plist) start top-reduction-only)))
	(ideal-polysaturation-1 ring G (rest plist) (length G) top-reduction-only)))))

(defun ideal-saturation (ring F G start &optional (top-reduction-only $poly_top_reduction_only)
			 &aux
			 (k (length G))
			 (*monomial-order* (or *elimination-order*
					       (elimination-order k))))
  "Returns the reduced Grobner basis of the saturation of the ideal
generated by a polynomial list F in the ideal generated a polynomial
list G. The saturation ideal is defined as the set of polynomials H
such for some natural number n and some P in the ideal generated by G
the polynomial P**N * H is in the ideal spanned by F.  Geometrically,
over an algebraically closed field, this is the set of polynomials in
the ideal generated by F which do not identically vanish on the
variety of G."
  (mapcar
   #'(lambda (q) (poly-contract q k))
   (ring-intersection
    (reduced-grobner ring
		     (polysaturation-extension ring F G)
		     start
		     top-reduction-only)
    k)))

(defun ideal-polysaturation (ring F ideal-list start &optional (top-reduction-only $poly_top_reduction_only))
    "Returns the reduced Grobner basis of the ideal obtained by a
successive applications of IDEAL-SATURATION to F and lists of
polynomials in the list IDEAL-LIST."
  (cond
   ((endp ideal-list) F)
   (t (let ((H (ideal-saturation ring F (car ideal-list) start top-reduction-only)))
	(ideal-polysaturation ring H (rest ideal-list) (length H) top-reduction-only)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Set up the coefficients to be polynomials
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (defun poly-ring (ring vars)
;;   (make-ring 
;;    :parse #'(lambda (expr) (poly-eval ring expr vars))
;;    :unit #'(lambda () (poly-unit ring (length vars)))
;;    :zerop #'poly-zerop
;;    :add #'(lambda (x y) (poly-add ring x y))
;;    :sub #'(lambda (x y) (poly-sub ring x y))
;;    :uminus #'(lambda (x) (poly-uminus ring x))
;;    :mul #'(lambda (x y) (poly-mul ring x y))
;;    :div #'(lambda (x y) (poly-exact-divide ring x y))
;;    :lcm #'(lambda (x y) (poly-lcm ring x y))
;;    :ezgcd #'(lambda (x y &aux (gcd (poly-gcd ring x y)))
;; 	      (values gcd
;; 		      (poly-exact-divide ring x gcd)
;; 		      (poly-exact-divide ring y gcd)))
;;    :gcd #'(lambda (x y) (poly-gcd x y))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Conversion from internal to infix form
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun coerce-to-infix (poly-type object vars)
  (case poly-type
    (:termlist
     `(+ ,@(mapcar #'(lambda (term) (coerce-to-infix :term term vars)) object)))
    (:polynomial
     (coerce-to-infix :termlist (poly-termlist object) vars))
    (:poly-list
     `([ ,@(mapcar #'(lambda (p) (coerce-to-infix :polynomial p vars)) object)))
    (:term
     `(* ,(term-coeff object)
	 ,@(mapcar #'(lambda (var power) `(expt ,var ,power))
		   vars (monom-exponents (term-monom object)))))
    (otherwise
     object)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Maxima expression ring
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defparameter *ExpressionRing*
    (make-ring 
     ;;(defun coeff-zerop (expr) (meval1 `(($is) (($equal) ,expr 0))))
     :parse #'(lambda (expr)
		(when modulus (setf expr ($rat expr)))
		expr)
     :unit #'(lambda () (if modulus ($rat 1) 1))
     :zerop #'(lambda (expr)
		;;When is exactly a maxima expression equal to 0?
		(cond ((numberp expr)
		       (= expr 0))
		      ((atom expr) nil)
		      (t
		       (case (caar expr)
			 (mrat (eql ($ratdisrep expr) 0))
			 (otherwise (eql ($totaldisrep expr) 0))))))
     :add #'(lambda (x y) (m+ x y))
     :sub #'(lambda (x y) (m- x y))
     :uminus #'(lambda (x) (m- x))
     :mul #'(lambda (x y) (m* x y))
     ;;(defun coeff-div (x y) (cadr ($divide x y)))
     :div #'(lambda (x y) (m// x y))
     :lcm #'(lambda (x y) (meval1 `((|$lcm|) ,x ,y)))
     :ezgcd #'(lambda (x y) (apply #'values (cdr ($ezgcd x y))))
     :gcd #'(lambda (x y) (second ($ezgcd x y)))))

(defvar *MaximaRing* *ExpressionRing*
  "The ring of coefficients, over which all polynomials 
are assumed to be defined.")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Maxima expression parsing
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun equal-test-p (expr1 expr2)
  (alike1 expr1 expr2))

(defun coerce-maxima-list (expr)
  "Convert a Maxima list to Lisp list."
  (cond
   ((and (consp (car expr)) (eql (caar expr) 'mlist)) (cdr expr))
   (t expr)))

(defun free-of-vars (expr vars) (apply #'$freeof `(,@vars ,expr)))

(defun parse-poly (expr vars &aux (vars (coerce-maxima-list vars)))
  "Convert a maxima polynomial expression EXPR in variables VARS to internal form."
  (labels ((parse (arg) (parse-poly arg vars))
	   (parse-list (args) (mapcar #'parse args)))
    (cond
     ((eql expr 0) (make-poly-zero))
     ((member expr vars :test #'equal-test-p)
      (let ((pos (position expr vars :test #'equal-test-p)))
	(make-variable *MaximaRing* (length vars) pos)))
     ((free-of-vars expr vars)
      ;;This means that variable-free CRE and Poisson forms will be converted
      ;;to coefficients intact
      (coerce-coeff *MaximaRing* expr vars))
     (t
      (case (caar expr)
	(mplus (reduce #'(lambda (x y) (poly-add *MaximaRing* x y)) (parse-list (cdr expr))))
	(mminus (poly-uminus *MaximaRing* (parse (cadr expr))))
	(mtimes
	 (if (endp (cddr expr))		;unary
	     (parse (cdr expr))
	   (reduce #'(lambda (p q) (poly-mul *MaximaRing* p q)) (parse-list (cdr expr)))))
	(mexpt
	 (cond
	  ((member (cadr expr) vars :test #'equal-test-p)
	   ;;Special handling of (expt var pow)
	   (let ((pos (position (cadr expr) vars :test #'equal-test-p)))
	     (make-variable *MaximaRing* (length vars) pos (caddr expr))))
	  ((not (and (integerp (caddr expr)) (plusp (caddr expr))))
	   ;; Negative power means division in coefficient ring
	   ;; Non-integer power means non-polynomial coefficient
	   (mtell "~%Warning: Expression ~%~M~%contains power which is not a positive integer. Parsing as coefficient.~%"
		  expr)
	   (coerce-coeff *MaximaRing* expr vars))
	  (t (poly-expt *MaximaRing* (parse (cadr expr)) (caddr expr)))))
	(mrat (parse ($ratdisrep expr)))
	(mpois (parse ($outofpois expr)))
	(otherwise
	 (coerce-coeff *MaximaRing* expr vars)))))))

(defun parse-poly-list (expr vars)
  (case (caar expr)
    (mlist (mapcar #'(lambda (p) (parse-poly p vars)) (cdr expr)))
    (t (merror "Expression ~M is not a list of polynomials in variables ~M."
	       expr vars))))
(defun parse-poly-list-list (poly-list-list vars)
  (mapcar #'(lambda (G) (parse-poly-list G vars)) (coerce-maxima-list poly-list-list)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Order utilities
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun find-order (order)
  "This function returns the order function bases on its name."
  (cond
   ((null order) NIL)
   ((symbolp order)
    (case order
      ((lex :lex $lex) #'lex>) 
      ((grlex :grlex $grlex) #'grlex>)
      ((grevlex :grevlex $grevlex) #'grevlex>)
      ((invlex :invlex $invlex) #'invlex>)
      ((elimination-order-1 :elimination-order-1 elimination_order_1) #'elimination-order-1)
      (otherwise
       (mtell "~%Warning: Order ~M not found. Using default.~%" order))))
   (t
    (mtell "~%Order specification ~M is not recognized. Using default.~%" order)
    NIL)))

(defun find-ring (ring)
  "This function returns the ring structure bases on input symbol."
  (cond
   ((null ring) NIL)
   ((symbolp ring)
    (case ring
      ((expression-ring :expression-ring $expression_ring) *ExpressionRing*) 
      ((ring-of-integers :ring-of-integers $ring_of_integers) *RingOfIntegers*) 
      (otherwise
       (mtell "~%Warning: Ring ~M not found. Using default.~%" ring))))
   (t
    (mtell "~%Ring specification ~M is not recognized. Using default.~%" ring)
    NIL)))

(defmacro with-monomial-order ((order) &body body)
  "Evaluate BODY with monomial order set to ORDER."
  `(let ((*monomial-order* (or (find-order ,order) *monomial-order*)))
     . ,body))

(defmacro with-coefficient-ring ((ring) &body body)
  "Evaluate BODY with coefficient ring set to RING."
  `(let ((*MaximaRing* (or (find-ring ,ring) *MaximaRing*)))
     . ,body))

(defmacro with-elimination-orders ((primary secondary elimination-order)
				   &body body)
  "Evaluate BODY with primary and secondary elimination orders set to PRIMARY and SECONDARY."
  `(let ((*primary-elimination-order* (or (find-order ,primary)  *primary-elimination-order*))
	 (*secondary-elimination-order* (or (find-order ,secondary) *secondary-elimination-order*))
	 (*elimination-order* (or (find-order ,elimination-order) *elimination-order*)))
     . ,body))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Conversion from internal form to Maxima general form
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun maxima-head ()
  (if $poly_return_term_list
      '(mlist)
    '(mplus)))

(defun coerce-to-maxima (poly-type object vars)
  (case poly-type
    (:polynomial 
     `(,(maxima-head) ,@(mapcar #'(lambda (term) (coerce-to-maxima :term term vars)) (poly-termlist object))))
    (:poly-list
     `((mlist) ,@(mapcar #'(lambda (p) (coerce-to-maxima :polynomial p vars)) object)))
    (:term
     `((mtimes) ,(term-coeff object)
		,@(mapcar #'(lambda (var power) `((mexpt) ,var ,power))
			  vars (monom-exponents (term-monom object)))))
    (otherwise
     object)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Macro facility for writing Maxima-level wrappers for
;; functions operating on internal representation
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmacro with-parsed-polynomials (((maxima-vars &optional (maxima-new-vars nil new-vars-supplied-p))
				    &key (polynomials nil)
					 (poly-lists nil)
					 (poly-list-lists nil)
					 (value-type nil))
				   &body body
				   &aux (vars (gensym))
					(new-vars (gensym)))
  `(let ((,vars (coerce-maxima-list ,maxima-vars))
	 ,@(when new-vars-supplied-p
	     (list `(,new-vars (coerce-maxima-list ,maxima-new-vars)))))
     (coerce-to-maxima
      ,value-type
      (with-coefficient-ring ($poly_coefficient_ring)
	(with-monomial-order ($poly_monomial_order)
	  (with-elimination-orders ($poly_primary_elimination_order
				    $poly_secondary_elimination_order
				    $poly_elimination_order)
	    (let ,(let ((args nil))
		    (dolist (p polynomials args)
		      (setf args (cons `(,p (parse-poly ,p ,vars)) args)))
		    (dolist (p poly-lists args)
		      (setf args (cons `(,p (parse-poly-list ,p ,vars)) args)))
		    (dolist (p poly-list-lists args)
		      (setf args (cons `(,p (parse-poly-list-list ,p ,vars)) args))))
	      . ,body))))
      ,(if new-vars-supplied-p
	   `(append ,vars ,new-vars)
	 vars))))

(defmacro define-unop (maxima-name fun-name
		       &optional (documentation nil documentation-supplied-p))
  "Define a MAXIMA-level unary operator MAXIMA-NAME corresponding to unary function FUN-NAME."
  `(defun ,maxima-name (p vars
			     &aux
			     (vars (coerce-maxima-list vars))
			     (p (parse-poly p vars)))
     ,@(when documentation-supplied-p (list documentation))
     (coerce-to-maxima :polynomial (,fun-name *MaximaRing* p) vars)))

(defmacro define-binop (maxima-name fun-name
			&optional (documentation nil documentation-supplied-p))
  "Define a MAXIMA-level binary operator MAXIMA-NAME corresponding to binary function FUN-NAME."
  `(defmfun ,maxima-name (p q vars
			     &aux
			     (vars (coerce-maxima-list vars))
			     (p (parse-poly p vars))
			     (q (parse-poly q vars)))
     ,@(when documentation-supplied-p (list documentation))
     (coerce-to-maxima :polynomial (,fun-name *MaximaRing* p q) vars)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Maxima-level interface functions
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Auxillary function for removing zero polynomial
(defun remzero (plist) (remove #'poly-zerop plist))

;;Simple operators

(define-binop $poly_add poly-add
  "Adds two polynomials P and Q")

(define-binop $poly_subtract poly-sub
  "Subtracts a polynomial Q from P.")

(define-binop $poly_multiply poly-mul
  "Returns the product of polynomials P and Q.")

(define-binop $poly_s_polynomial spoly
  "Returns the syzygy polynomial (S-polynomial) of two polynomials P and Q.")

(define-unop $poly_primitive_part poly-primitive-part
  "Returns the polynomial P divided by GCD of its coefficients.")

(define-unop $poly_normalize poly-normalize
  "Returns the polynomial P divided by the leading coefficient.")

;;Functions

(defmfun $poly_expand (p vars)
  "This function is equivalent to EXPAND(P) if P parses correctly to a polynomial.
If the representation is not compatible with a polynomial in variables VARS,
the result is an error."
  (with-parsed-polynomials ((vars) :polynomials (p)
			    :value-type :polynomial)
			   p))

(defmfun $poly_expt (p n vars)
  (with-parsed-polynomials ((vars) :polynomials (p) :value-type :polynomial)
    (poly-expt *MaximaRing* p n)))

(defmfun $poly_content (p vars)
  (with-parsed-polynomials ((vars) :polynomials (p))
    (poly-content *MaximaRing* p)))

(defmfun $poly_pseudo_divide (f fl vars
			    &aux (vars (coerce-maxima-list vars))
				 (f (parse-poly f vars))
				 (fl (parse-poly-list fl vars)))
  (multiple-value-bind (quot rem c division-count)
      (poly-pseudo-divide *MaximaRing* f fl)
    `((mlist)
      ,(coerce-to-maxima :poly-list quot vars)
      ,(coerce-to-maxima :polynomial rem vars)
      ,c
      ,division-count)))

(defmfun $poly_exact_divide (f g vars)
  (with-parsed-polynomials ((vars) :polynomials (f g) :value-type :polynomial)
    (poly-exact-divide *MaximaRing* f g)))

(defmfun $poly_normal_form (f fl vars)
  (with-parsed-polynomials ((vars) :polynomials (f)
				   :poly-lists (fl)
				   :value-type :polynomial)
    (normal-form *MaximaRing* f (remzero fl) nil)))

(defmfun $poly_buchberger_criterion (G vars)
  (with-parsed-polynomials ((vars) :poly-lists (G))
    (buchberger-criterion *MaximaRing* G)))

(defmfun $poly_buchberger (fl vars)
  (with-parsed-polynomials ((vars) :poly-lists (fl) :value-type :poly-list)
    (buchberger *MaximaRing*  (remzero fl) 0 nil)))

(defmfun $poly_reduction (plist vars)
  (with-parsed-polynomials ((vars) :poly-lists (plist)
				   :value-type :poly-list)
    (reduction *MaximaRing* plist)))

(defmfun $poly_minimization (plist vars)
  (with-parsed-polynomials ((vars) :poly-lists (plist)
				   :value-type :poly-list)
    (minimization plist)))

(defmfun $poly_normalize_list (plist vars)
  (with-parsed-polynomials ((vars) :poly-lists (plist)
				   :value-type :poly-list)
    (poly-normalize-list *MaximaRing* plist)))

(defmfun $poly_grobner (F vars)
  (with-parsed-polynomials ((vars) :poly-lists (F)
				   :value-type :poly-list)
    (grobner *MaximaRing* (remzero F))))

(defmfun $poly_reduced_grobner (F vars)
  (with-parsed-polynomials ((vars) :poly-lists (F)
				   :value-type :poly-list)
    (reduced-grobner *MaximaRing* (remzero F))))

(defmfun $poly_depends_p (p var mvars
			&aux (vars (coerce-maxima-list mvars))
			     (pos (position var vars)))
  (if (null pos)
      (merror "~%Variable ~M not in the list of variables ~M." var mvars)
    (poly-depends-p (parse-poly p vars) pos)))

(defmfun $poly_elimination_ideal (flist k vars)
  (with-parsed-polynomials ((vars) :poly-lists (flist)
				   :value-type :poly-list)
    (elimination-ideal *MaximaRing* flist k nil 0)))

(defmfun $poly_colon_ideal (F G vars)
  (with-parsed-polynomials ((vars) :poly-lists (F G) :value-type :poly-list)
    (colon-ideal *MaximaRing* F G nil)))

(defmfun $poly_ideal_intersection (F G vars)
  (with-parsed-polynomials ((vars) :poly-lists (F G) :value-type :poly-list)  
    (ideal-intersection *MaximaRing* F G nil)))

(defmfun $poly_lcm (f g vars)
  (with-parsed-polynomials ((vars) :polynomials (f g) :value-type :polynomial)
    (poly-lcm *MaximaRing* f g)))

(defmfun $poly_gcd (f g vars)
  ($first ($divide (m* f g) ($poly_lcm f g vars))))

(defmfun $poly_grobner_equal (G1 G2 vars)
  (with-parsed-polynomials ((vars) :poly-lists (G1 G2))
    (grobner-equal *MaximaRing* G1 G2)))

(defmfun $poly_grobner_subsetp (G1 G2 vars)
  (with-parsed-polynomials ((vars) :poly-lists (G1 G2))
    (grobner-subsetp *MaximaRing* G1 G2)))

(defmfun $poly_grobner_member (p G vars)
  (with-parsed-polynomials ((vars) :polynomials (p) :poly-lists (G))
    (grobner-member *MaximaRing* p G)))

(defmfun $poly_ideal_saturation1 (F p vars)
  (with-parsed-polynomials ((vars) :poly-lists (F) :polynomials (p)
				   :value-type :poly-list)
    (ideal-saturation-1 *MaximaRing* F p)))

(defmfun $poly_saturation_extension (F plist vars new-vars)
  (with-parsed-polynomials ((vars new-vars)
			    :poly-lists (F plist)
			    :value-type :poly-list)
    (saturation-extension *MaximaRing* F plist)))

(defmfun $poly_polysaturation_extension (F plist vars new-vars)
  (with-parsed-polynomials ((vars new-vars)
			    :poly-lists (F plist)
			    :value-type :poly-list)
    (polysaturation-extension *MaximaRing* F plist)))

(defmfun $poly_ideal_polysaturation1 (F plist vars)
  (with-parsed-polynomials ((vars) :poly-lists (F plist)
				   :value-type :poly-list)
    (ideal-polysaturation-1 *MaximaRing* F plist 0 nil)))

(defmfun $poly_ideal_saturation (F G vars)
  (with-parsed-polynomials ((vars) :poly-lists (F G)
				   :value-type  :poly-list)
    (ideal-saturation *MaximaRing* F G 0 nil)))

(defmfun $poly_ideal_polysaturation (F ideal-list vars)
  (with-parsed-polynomials ((vars) :poly-lists (F)
				   :poly-list-lists (ideal-list)
				   :value-type :poly-list)
    (ideal-polysaturation *MaximaRing* F ideal-list 0 nil)))

