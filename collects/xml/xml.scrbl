#lang scribble/doc
@(require scribble/manual
          scribble/bnf
          scribble/eval
          (for-label scheme/base
                     scheme/contract
                     scheme/list
                     xml
                     xml/plist))

@(define xml-eval (make-base-eval))
@(define plist-eval (make-base-eval))
@interaction-eval[#:eval xml-eval (require xml)]
@interaction-eval[#:eval xml-eval (require scheme/list)]
@interaction-eval[#:eval plist-eval (require xml/plist)]

@title{@bold{XML}: Parsing and Writing}

@author["Paul Graunke and Jay McCarthy"]

@defmodule[xml]

The @schememodname[xml] library provides functions for parsing and
generating XML. XML can be represented as an instance of the
@scheme[document] structure type, or as a kind of S-expression that is
called an @deftech{X-expression}.

The @schememodname[xml] library does not provide Document Type
Declaration (DTD) processing, including preservation of DTDs in read documents, or validation.
It also does not expand user-defined entities or read user-defined entities in attributes.

@; ----------------------------------------------------------------------

@section{Datatypes}

@defproc[(xexpr? [v any/c]) boolean?]{

Returns @scheme[#t] if @scheme[v] is a @tech{X-expression}, @scheme[#f] otherwise.

The following grammar describes expressions that create @tech{X-expressions}:

@schemegrammar[
#:literals (cons list)
xexpr string
      (list symbol (list (list symbol string) ...) xexpr ...)
      (cons symbol (list xexpr ...))
      symbol
      exact-nonnegative-integer
      cdata
      misc
]

A @scheme[_string] is literal data. When converted to an XML stream,
the characters of the data will be escaped as necessary.

A pair represents an element, optionally with attributes. Each
attribute's name is represented by a symbol, and its value is
represented by a string.

A @scheme[_symbol] represents a symbolic entity. For example,
@scheme['nbsp] represents @litchar{&nbsp;}.

An @scheme[_exact-nonnegative-integer] represents a numeric entity. For example,
@schemevalfont{#x20} represents @litchar{&#20;}.

A @scheme[_cdata] is an instance of the @scheme[cdata] structure type,
and a @scheme[_misc] is an instance of the @scheme[comment] or
@scheme[pcdata] structure types.}

@defthing[xexpr/c contract?]{
 A contract that is like @scheme[xexpr?] except produces a better error message when the value is not an @tech{X-expression}.
}   

@defstruct[document ([prolog prolog?]
                     [element element?]
                     [misc (listof (or/c comment? p-i?))])]{

Represents a document.}

@defstruct[prolog ([misc (listof (or/c comment? p-i?))]
                   [dtd (or/c document-type false/c)]
                   [misc2 (listof (or/c comment? p-i?))])]{

Represents a document prolog. The @scheme[make-prolog] binding is
unusual: it accepts two or more arguments, and all arguments after the
first two are collected into the @scheme[misc2] field.

@examples[
#:eval xml-eval
(make-prolog empty #f)
(make-prolog empty #f (make-p-i #f #f "k1" "v1"))
(make-prolog empty #f (make-p-i #f #f "k1" "v1")
             (make-p-i #f #f "k2" "v2"))
@(code:comment "This example breaks the contract by providing")
@(code:comment "a list rather than a comment or p-i")
(prolog-misc2 (make-prolog empty #f empty))
]
}

@defstruct[document-type ([name symbol?]
                          [external external-dtd?]
                          [inlined false/c])]{

Represents a document type.}

@deftogether[(
@defstruct[external-dtd ([system string?])]
@defstruct[(external-dtd/public external-dtd) ([public string?])]
@defstruct[(external-dtd/system external-dtd) ()]
)]{

Represents an externally defined DTD.}

@defstruct[(element source) ([name symbol?]
                             [attributes (listof attribute?)]
                             [content (listof content?)])]{

Represents an element.}

@defproc[(content? [v any/c]) boolean?]{

Returns @scheme[#t] if @scheme[v] is a @scheme[pcdata] instance,
@scheme[element] instance, an @scheme[entity] instance,
@scheme[comment], or @scheme[cdata] instance.}

@defstruct[(attribute source) ([name symbol?] [value string?])]{

Represents an attribute within an element.}

@defstruct[(entity source) ([text (or/c symbol? exact-nonnegative-integer?)])]{

Represents a symbolic or numerical entity.}

@defstruct[(pcdata source) ([string string?])]{

Represents PCDATA content.}


@defstruct[(cdata source) ([string string?])]{

Represents CDATA content.

The @scheme[string] field is assumed to be of the form
@litchar{<![CDATA[}@nonterm{content}@litchar{]]>} with proper quoting
of @nonterm{content}. Otherwise, @scheme[write-xml] generates
incorrect output.}

@defstruct[(p-i source) ([target-name string?]
                         [instruction string?])]{

Represents a processing instruction.}


@defstruct[comment ([text string?])]{

Represents a comment.}


@defstruct[source ([start (or/c location? symbol?)]
                   [stop (or/c location? symbol?)])]{

Represents a source location. Other structure types extend @scheme[source].

When XML is generated from an input stream by @scheme[read-xml],
locations are represented by @scheme[location] instances. When XML
structures are generated by @scheme[xexpr->xml], then locations are
symbols.}


@defstruct[location ([line exact-nonnegative-integer?]
                     [char exact-nonnegative-integer?]
                     [offset exact-nonnegative-integer?])]{

Represents a location in an input stream.}


@defstruct[(exn:invalid-xexpr exn:fail) ([code any/c])]{

Raised by @scheme[validate-xexpr] when passed an invalid
@tech{X-expression}. The @scheme[code] fields contains an invalid part
of the input to @scheme[validate-xexpr].}

@; ----------------------------------------------------------------------

@section{Reading and Writing XML}

@defproc[(read-xml [in input-port? (current-input-port)]) document?]{

Reads in an XML document from the given or current input port XML
documents contain exactly one element, raising @scheme[xml-read:error]
if the input stream has zero elements or more than one element.
       
Malformed xml is reported with source locations in the form
@nonterm{l}@litchar{.}@nonterm{c}@litchar{/}@nonterm{o}, where
@nonterm{l}, @nonterm{c}, and @nonterm{o} are the line number, column
number, and next port position, respectively as returned by
@scheme[port-next-location].

Any non-characters other than @scheme[eof] read from the input-port
appear in the document content.  Such special values may appear only
where XML content may.  See @scheme[make-input-port] for information
about creating ports that return non-character values.

@examples[
#:eval xml-eval
(xml->xexpr (document-element 
             (read-xml (open-input-string 
                        "<doc><bold>hi</bold> there!</doc>"))))
]}

@defproc[(read-xml/element [in input-port? (current-input-port)]) element?]{

Reads a single XML element from the port.  The next non-whitespace
character read must start an XML element, but the input port can
contain other data after the element.}

@defproc[(syntax:read-xml [in input-port? (current-input-port)]) syntax?]{

Reads in an XML document and produces a syntax object version (like
@scheme[read-syntax]) of an @tech{X-expression}.}

@defproc[(syntax:read-xml/element [in input-port? (current-input-port)]) syntax?]{

Like @scheme[syntax:real-xml], but it reads an XML element like
@scheme[read-xml/element].}

@defproc[(write-xml [doc document?] [out output-port? (current-output-port)])
         void?]{

Writes a document to the given output port, currently ignoring
everything except the document's root element.}

@defproc[(write-xml/content [content content?] [out output-port? (current-output-port)])
         void?]{

Writes document content to the given output port.}

@defproc[(display-xml [doc document?] [out output-port? (current-output-port)])
         void?]{

Like @scheme[write-xml], but newlines and indentation make the output
more readable, though less technically correct when whitespace is
significant.}

@defproc[(display-xml/content [content content?] [out output-port? (current-output-port)])
         void?]{

Like @scheme[write-xml/content], but with indentation and newlines
like @scheme[display-xml].}


@; ----------------------------------------------------------------------

@section{XML and X-expression Conversions}

@defboolparam[permissive? v]{
 If this is set to non-false, then @scheme[xml->xexpr] will allow
 non-XML objects, such as other structs, in the content of the converted XML
 and leave them in place in the resulting ``@tech{X-expression}''.
}
                             
@defproc[(xml->xexpr [content content?]) xexpr/c]{

Converts document content into an @tech{X-expression}, using
@scheme[permissive?] to determine if foreign objects are allowed.}

@defproc[(xexpr->xml [xexpr xexpr/c]) content?]{

Converts an @tech{X-expression} into XML content.}

@defproc[(xexpr->string [xexpr xexpr/c]) string?]{

Converts an @tech{X-expression} into a string containing XML.}

@defproc[((eliminate-whitespace [tags (listof symbol?)]
                                [choose (boolean? . -> . any/c)])
          [elem element?])
         element?]{

Some elements should not contain any text, only other tags, except
they often contain whitespace for formating purposes.  Given a list of
tag names as @scheme[tag]s and the identity function as
@scheme[choose], @scheme[eliminate-whitespace] produces a function
that filters out PCDATA consisting solely of whitespace from those
elements, and it raises an error if any non-whitespace text appears.
Passing in @scheme[not] as @scheme[choose] filters all elements which
are not named in the @scheme[tags] list.  Using @scheme[void] as
@scheme[choose] filters all elements regardless of the @scheme[tags]
list.}

@defproc[(validate-xexpr [v any/c]) (one-of/c #t)]{

If @scheme[v] is an @tech{X-expression}, the result
@scheme[#t]. Otherwise, @scheme[exn:invalid-xexpr]s is raised, with
the a message of the form ``Expected @nonterm{something}, given
@nonterm{something-else}/'' The @scheme[code] field of the exception
is the part of @scheme[v] that caused the exception.}

@defproc[(correct-xexpr? [v any/c]
                         [success-k (-> any/c)]
                         [fail-k (exn:invalid-xexpr? . -> . any/c)])
         any/c]{

Like @scheme[validate-expr], except that @scheme[success-k] is called
on each valid leaf, and @scheme[fail-k] is called on invalid leaves;
the @scheme[fail-k] may return a value instead of raising an exception
of otherwise escaping. Results from the leaves are combined with
@scheme[and] to arrive at the final result.}

@; ----------------------------------------------------------------------

@section{Parameters}

@defparam[empty-tag-shorthand shorthand (or/c (one-of/c 'always 'never) (listof symbol?))]{

A parameter that determines whether output functions should use the
@litchar{<}@nonterm{tag}@litchar{/>} tag notation instead of
@litchar{<}@nonterm{tag}@litchar{>}@litchar{</}@nonterm{tag}@litchar{>}
for elements that have no content.

When the parameter is set to @scheme['always], the abbreviated
notation is always used. When set of @scheme['never], the abbreviated
notation is never generated.  when set to a list of symbols is
provided, tags with names in the list are abbreviated.  The default is
@scheme['always].

The abbreviated form is the preferred XML notation.  However, most
browsers designed for HTML will only properly render XHTML if the
document uses a mixture of the two formats. The
@scheme[html-empty-tags] constant contains the W3 consortium's
recommended list of XHTML tags that should use the shorthand.}

@defthing[html-empty-tags (listof symbol?)]{

See @scheme[empty-tag-shorthand].

@examples[
#:eval xml-eval
(parameterize ([empty-tag-shorthand html-empty-tags])
  (write-xml/content (xexpr->xml `(html 
                                    (body ((bgcolor "red"))
                                      "Hi!" (br) "Bye!")))))
]}

@defboolparam[collapse-whitespace collapse?]{

A parameter that controls whether consecutive whitespace is replaced
by a single space.  CDATA sections are not affected. The default is
@scheme[#f].}

@defboolparam[read-comments preserve?]{

A parameter that determines whether comments are preserved or
discarded when reading XML.  The default is @scheme[#f], which
discards comments.}

@defboolparam[xexpr-drop-empty-attributes drop?]{

Controls whether @scheme[xml->xexpr] drops or preserves attribute
sections for an element that has no attributes. The default is
@scheme[#f], which means that all generated @tech{X-expression}
elements have an attributes list (even if it's empty).}

@; ----------------------------------------------------------------------

@section{PList Library}

@defmodule[xml/plist]

The @schememodname[xml/plist] library provides the ability to read and
write XML documents that conform to the @defterm{plist} DTD, which is
used to store dictionaries of string--value associations.  This format
is used by Mac OS X (both the operating system and its applications)
to store all kinds of data.

A @deftech{plist dictionary} is a value that could be created by an
expression matching the following @scheme[_dict-expr] grammar:

@schemegrammar*[
#:literals (list)
[dict-expr (list 'dict assoc-pair ...)]
[assoc-pair (list 'assoc-pair string pl-value)]
[pl-value string
          (list 'true)
          (list 'false)
          (list 'integer integer)
          (list 'real real)
          dict-expr
          (list 'array pl-value ...)]
]

@defproc[(plist-dict? [any/c v]) boolean?]{

Returns @scheme[#t] if @scheme[v] is a @tech{plist dictionary},
@scheme[#f] otherwise.}

@defproc[(read-plist [in input-port?]) plist-dict?]{

Reads a plist from a port, and produces a @tech{plist dictionary}.}

@defproc[(write-plist [dict plist-dict?] [out output-port?]) void?]{

Write a @tech{plist dictionary} to the given port.}

@examples[
#:eval plist-eval
(define my-dict
  `(dict (assoc-pair "first-key"
                     "just a string with some  whitespace")
         (assoc-pair "second-key"
                     (false))
         (assoc-pair "third-key"
                     (dict ))
         (assoc-pair "fourth-key"
                     (dict (assoc-pair "inner-key"
                                       (real 3.432))))
         (assoc-pair "fifth-key"
                     (array (integer 14)
                            "another string"
                            (true)))
         (assoc-pair "sixth-key"
                     (array))))
(define-values (in out) (make-pipe))
(write-plist my-dict out)
(close-output-port out)
(define new-dict (read-plist in))
(equal? my-dict new-dict)
]

The XML generated by @scheme[write-plist] in the above example
looks like the following, if re-formatted by:

@verbatim[#:indent 2]|{
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist SYSTEM 
 "file://localhost/System/Library/DTDs/PropertyList.dtd">
<plist version="0.9">
  <dict>
    <key>first-key</key>
    <string>just a string with some  whitespace</string>
    <key>second-key</key>
    <false />
    <key>third-key</key>
    <dict />
    <key>fourth-key</key>
    <dict>
      <key>inner-key</key>
      <real>3.432</real>
    </dict>
    <key>fifth-key</key>
    <array>
      <integer>14</integer>
      <string>another string</string>
      <true />
    </array>
    <key>sixth-key</key>
    <array />
  </dict>
</plist>
}|
