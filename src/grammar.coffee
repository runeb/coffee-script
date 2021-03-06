Parser: require('jison').Parser

# DSL ===================================================================

# Detect functions: [
unwrap: /function\s*\(\)\s*\{\s*return\s*([\s\S]*);\s*\}/

# Quickie DSL for Jison access.
o: (pattern_string, func, options) ->
  if func
    func: if match: (func + "").match(unwrap) then match[1] else '(' + func + '())'
    [pattern_string, '$$ = ' + func + ';', options]
  else
    [pattern_string, '$$ = $1;', options]

# Precedence ===========================================================

operators: [
  ["left",      '?']
  ["nonassoc",  'UMINUS', 'UPLUS', 'NOT', '!', '!!', '~', '++', '--']
  ["left",      '*', '/', '%']
  ["left",      '+', '-']
  ["left",      '<<', '>>', '>>>']
  ["left",      '&', '|', '^']
  ["left",      '<=', '<', '>', '>=']
  ["right",     'DELETE', 'INSTANCEOF', 'TYPEOF']
  ["right",     '==', '!=', 'IS', 'ISNT']
  ["left",      '&&', '||', 'AND', 'OR']
  ["right",     '-=', '+=', '/=', '*=', '%=', '||=', '&&=', '?=']
  ["left",      '.']
  ["right",     'INDENT']
  ["left",      'OUTDENT']
  ["right",     'WHEN', 'LEADING_WHEN', 'IN', 'OF', 'BY', 'THROW']
  ["right",     'FOR', 'NEW', 'SUPER', 'CLASS']
  ["left",      'EXTENDS']
  ["right",     'ASSIGN', 'RETURN']
  ["right",     '->', '=>', 'UNLESS', 'IF', 'ELSE', 'WHILE']
]

# Grammar ==============================================================

grammar: {

  # All parsing will end in this rule, being the trunk of the AST.
  Root: [
    o "",                                  -> new Expressions()
    o "TERMINATOR",                        -> new Expressions()
    o "Expressions",                       -> $1
    o "Block TERMINATOR",                  -> $1
  ]

  # Any list of expressions or method body, seperated by line breaks or semis.
  Expressions: [
    o "Expression",                        -> Expressions.wrap([$1])
    o "Expressions TERMINATOR Expression", -> $1.push($3)
    o "Expressions TERMINATOR",            -> $1
  ]

  # All types of expressions in our language. The basic unit of CoffeeScript
  # is the expression.
  Expression: [
    o "Value"
    o "Call"
    o "Code"
    o "Operation"
    o "Assign"
    o "If"
    o "Try"
    o "Throw"
    o "Return"
    o "While"
    o "For"
    o "Switch"
    o "Extends"
    o "Class"
    o "Splat"
    o "Existence"
    o "Comment"
  ]

  # A block of expressions. Note that the Rewriter will convert some postfix
  # forms into blocks for us, by altering the token stream.
  Block: [
    o "INDENT Expressions OUTDENT",             -> $2
    o "INDENT OUTDENT",                         -> new Expressions()
  ]

  Identifier: [
    o "IDENTIFIER",                             -> new LiteralNode(yytext)
  ]

  AlphaNumeric: [
    o "NUMBER",                                 -> new LiteralNode(yytext)
    o "STRING",                                 -> new LiteralNode(yytext)
  ]

  # All hard-coded values. These can be printed straight to JavaScript.
  Literal: [
    o "AlphaNumeric",                           -> $1
    o "JS",                                     -> new LiteralNode(yytext)
    o "REGEX",                                  -> new LiteralNode(yytext)
    o "BREAK",                                  -> new LiteralNode(yytext)
    o "CONTINUE",                               -> new LiteralNode(yytext)
    o "TRUE",                                   -> new LiteralNode(true)
    o "FALSE",                                  -> new LiteralNode(false)
    o "YES",                                    -> new LiteralNode(true)
    o "NO",                                     -> new LiteralNode(false)
    o "ON",                                     -> new LiteralNode(true)
    o "OFF",                                    -> new LiteralNode(false)
  ]

  # Assignment to a variable (or index).
  Assign: [
    o "Value ASSIGN Expression",                -> new AssignNode($1, $3)
  ]

  # Assignment within an object literal (can be quoted).
  AssignObj: [
    o "Identifier ASSIGN Expression",           -> new AssignNode(new ValueNode($1), $3, 'object')
    o "AlphaNumeric ASSIGN Expression",         -> new AssignNode(new ValueNode($1), $3, 'object')
    o "Comment"
  ]

  # A return statement.
  Return: [
    o "RETURN Expression",                      -> new ReturnNode($2)
    o "RETURN",                                 -> new ReturnNode(new ValueNode(new LiteralNode('null')))
  ]

  # A comment.
  Comment: [
    o "COMMENT",                                -> new CommentNode(yytext)
  ]

  # Arithmetic and logical operators
  # For Ruby's Operator precedence, see: [
  # https://www.cs.auckland.ac.nz/references/ruby/ProgrammingRuby/language.html
  Operation: [
    o "! Expression",                           -> new OpNode('!', $2)
    o "!! Expression",                          -> new OpNode('!!', $2)
    o("- Expression",                           (-> new OpNode('-', $2)), {prec: 'UMINUS'})
    o("+ Expression",                           (-> new OpNode('+', $2)), {prec: 'UPLUS'})
    o "NOT Expression",                         -> new OpNode('not', $2)
    o "~ Expression",                           -> new OpNode('~', $2)
    o "-- Expression",                          -> new OpNode('--', $2)
    o "++ Expression",                          -> new OpNode('++', $2)
    o "DELETE Expression",                      -> new OpNode('delete', $2)
    o "TYPEOF Expression",                      -> new OpNode('typeof', $2)
    o "Expression --",                          -> new OpNode('--', $1, null, true)
    o "Expression ++",                          -> new OpNode('++', $1, null, true)

    o "Expression * Expression",                -> new OpNode('*', $1, $3)
    o "Expression / Expression",                -> new OpNode('/', $1, $3)
    o "Expression % Expression",                -> new OpNode('%', $1, $3)

    o "Expression + Expression",                -> new OpNode('+', $1, $3)
    o "Expression - Expression",                -> new OpNode('-', $1, $3)

    o "Expression << Expression",               -> new OpNode('<<', $1, $3)
    o "Expression >> Expression",               -> new OpNode('>>', $1, $3)
    o "Expression >>> Expression",              -> new OpNode('>>>', $1, $3)
    o "Expression & Expression",                -> new OpNode('&', $1, $3)
    o "Expression | Expression",                -> new OpNode('|', $1, $3)
    o "Expression ^ Expression",                -> new OpNode('^', $1, $3)

    o "Expression <= Expression",               -> new OpNode('<=', $1, $3)
    o "Expression < Expression",                -> new OpNode('<', $1, $3)
    o "Expression > Expression",                -> new OpNode('>', $1, $3)
    o "Expression >= Expression",               -> new OpNode('>=', $1, $3)

    o "Expression == Expression",               -> new OpNode('==', $1, $3)
    o "Expression != Expression",               -> new OpNode('!=', $1, $3)
    o "Expression IS Expression",               -> new OpNode('is', $1, $3)
    o "Expression ISNT Expression",             -> new OpNode('isnt', $1, $3)

    o "Expression && Expression",               -> new OpNode('&&', $1, $3)
    o "Expression || Expression",               -> new OpNode('||', $1, $3)
    o "Expression AND Expression",              -> new OpNode('and', $1, $3)
    o "Expression OR Expression",               -> new OpNode('or', $1, $3)
    o "Expression ? Expression",                -> new OpNode('?', $1, $3)

    o "Expression -= Expression",               -> new OpNode('-=', $1, $3)
    o "Expression += Expression",               -> new OpNode('+=', $1, $3)
    o "Expression /= Expression",               -> new OpNode('/=', $1, $3)
    o "Expression *= Expression",               -> new OpNode('*=', $1, $3)
    o "Expression %= Expression",               -> new OpNode('%=', $1, $3)
    o "Expression ||= Expression",              -> new OpNode('||=', $1, $3)
    o "Expression &&= Expression",              -> new OpNode('&&=', $1, $3)
    o "Expression ?= Expression",               -> new OpNode('?=', $1, $3)

    o "Expression INSTANCEOF Expression",       -> new OpNode('instanceof', $1, $3)
    o "Expression IN Expression",               -> new OpNode('in', $1, $3)
  ]

  # The existence operator.
  Existence: [
    o "Expression ?",                           -> new ExistenceNode($1)
  ]

  # Function definition.
  Code: [
    o "PARAM_START ParamList PARAM_END FuncGlyph Block", -> new CodeNode($2, $5, $4)
    o "FuncGlyph Block",                        -> new CodeNode([], $2, $1)
  ]

  # The symbols to signify functions, and bound functions.
  FuncGlyph: [
    o "->",                                     -> 'func'
    o "=>",                                     -> 'boundfunc'
  ]

  # The parameters to a function definition.
  ParamList: [
    o "",                                       -> []
    o "Param",                                  -> [$1]
    o "ParamList , Param",                      -> $1.concat [$3]
  ]

  # A Parameter (or ParamSplat) in a function definition.
  Param: [
    o "PARAM",                                  -> new LiteralNode(yytext)
    o "Param . . .",                            -> new SplatNode($1)
  ]

  # A regular splat.
  Splat: [
    o "Expression . . .",                       -> new SplatNode($1)
  ]

  # Expressions that can be treated as values.
  Value: [
    o "Identifier",                             -> new ValueNode($1)
    o "Literal",                                -> new ValueNode($1)
    o "Array",                                  -> new ValueNode($1)
    o "Object",                                 -> new ValueNode($1)
    o "Parenthetical",                          -> new ValueNode($1)
    o "Range",                                  -> new ValueNode($1)
    o "This",                                   -> $1
    o "Value Accessor",                         -> $1.push($2)
    o "Invocation Accessor",                    -> new ValueNode($1, [$2])
  ]

  # Accessing into an object or array, through dot or index notation.
  Accessor: [
    o "PROPERTY_ACCESS Identifier",             -> new AccessorNode($2)
    o "PROTOTYPE_ACCESS Identifier",            -> new AccessorNode($2, 'prototype')
    o "SOAK_ACCESS Identifier",                 -> new AccessorNode($2, 'soak')
    o "Index"
    o "Slice",                                  -> new SliceNode($1)
  ]

  # Indexing into an object or array.
  Index: [
    o "INDEX_START Expression INDEX_END",       -> new IndexNode($2)
    o "SOAKED_INDEX_START Expression SOAKED_INDEX_END", -> new IndexNode($2, 'soak')
  ]

  # An object literal.
  Object: [
    o "{ AssignList }",                         -> new ObjectNode($2)
    o "{ IndentedAssignList }",                 -> new ObjectNode($2)
  ]

  # A class literal.
  Class: [
    o "CLASS Value",                            -> new ClassNode($2)
    o "CLASS Value EXTENDS Value",              -> new ClassNode($2, $4)
    o "CLASS Value IndentedAssignList",         -> new ClassNode($2, null, $3)
    o "CLASS Value EXTENDS Value IndentedAssignList", -> new ClassNode($2, $4, $5)
  ]

  # Assignment within an object literal (comma or newline separated).
  AssignList: [
    o "",                                       -> []
    o "AssignObj",                              -> [$1]
    o "AssignList , AssignObj",                 -> $1.concat [$3]
    o "AssignList TERMINATOR AssignObj",        -> $1.concat [$3]
    o "AssignList , TERMINATOR AssignObj",      -> $1.concat [$4]
  ]

  # A list of assignments in a block indentation.
  IndentedAssignList: [
    o "INDENT AssignList OUTDENT",              -> $2
  ]

  # All flavors of function call (instantiation, super, and regular).
  Call: [
    o "Invocation",                             -> $1
    o "NEW Invocation",                         -> $2.new_instance()
    o "Super",                                  -> $1
  ]

  # Extending an object's prototype.
  Extends: [
    o "Value EXTENDS Value",                    -> new ExtendsNode($1, $3)
  ]

  # A generic function invocation.
  Invocation: [
    o "Value Arguments",                        -> new CallNode($1, $2)
    o "Invocation Arguments",                   -> new CallNode($1, $2)
  ]

  # The list of arguments to a function invocation.
  Arguments: [
    o "CALL_START ArgList CALL_END",            -> $2
  ]

  # Calling super.
  Super: [
    o "SUPER CALL_START ArgList CALL_END",      -> new CallNode('super', $3)
  ]

  # This references, either naked or to a property.
  This: [
    o "@",                                      -> new ValueNode(new LiteralNode('this'))
    o "@ Identifier",                           -> new ValueNode(new LiteralNode('this'), [new AccessorNode($2)])
  ]

  # The range literal.
  Range: [
    o "[ Expression . . Expression ]",          -> new RangeNode($2, $5)
    o "[ Expression . . . Expression ]",        -> new RangeNode($2, $6, true)
  ]

  # The slice literal.
  Slice: [
    o "INDEX_START Expression . . Expression INDEX_END", -> new RangeNode($2, $5)
    o "INDEX_START Expression . . . Expression INDEX_END", -> new RangeNode($2, $6, true)
  ]

  # The array literal.
  Array: [
    o "[ ArgList ]",                            -> new ArrayNode($2)
  ]

  # A list of arguments to a method call, or as the contents of an array.
  ArgList: [
    o "",                                       -> []
    o "Expression",                             -> [$1]
    o "INDENT Expression",                      -> [$2]
    o "ArgList , Expression",                   -> $1.concat [$3]
    o "ArgList TERMINATOR Expression",          -> $1.concat [$3]
    o "ArgList , TERMINATOR Expression",        -> $1.concat [$4]
    o "ArgList , INDENT Expression",            -> $1.concat [$4]
    o "ArgList OUTDENT",                        -> $1
  ]

  # Just simple, comma-separated, required arguments (no fancy syntax).
  SimpleArgs: [
    o "Expression",                             -> $1
    o "SimpleArgs , Expression",                ->
      if $1 instanceof Array then $1.concat([$3]) else [$1].concat([$3])
  ]

  # Try/catch/finally exception handling blocks.
  Try: [
    o "TRY Block Catch",                        -> new TryNode($2, $3[0], $3[1])
    o "TRY Block FINALLY Block",                -> new TryNode($2, null, null, $4)
    o "TRY Block Catch FINALLY Block",          -> new TryNode($2, $3[0], $3[1], $5)
  ]

  # A catch clause.
  Catch: [
    o "CATCH Identifier Block",                 -> [$2, $3]
  ]

  # Throw an exception.
  Throw: [
    o "THROW Expression",                       -> new ThrowNode($2)
  ]

  # Parenthetical expressions.
  Parenthetical: [
    o "( Expression )",                         -> new ParentheticalNode($2)
  ]

  # The condition for a while loop.
  WhileSource: [
    o "WHILE Expression",                       -> new WhileNode($2)
    o "WHILE Expression WHEN Expression",       -> new WhileNode($2, {filter : $4})
  ]

  # The while loop. (there is no do..while).
  While: [
    o "WhileSource Block",                      -> $1.add_body $2
    o "Expression WhileSource",                 -> $2.add_body $1
  ]

  # Array comprehensions, including guard and current index.
  # Looks a little confusing, check nodes.rb for the arguments to ForNode.
  For: [
    o "Expression FOR ForVariables ForSource",  -> new ForNode($1, $4, $3[0], $3[1])
    o "FOR ForVariables ForSource Block",       -> new ForNode($4, $3, $2[0], $2[1])
  ]

  # An array comprehension has variables for the current element and index.
  ForVariables: [
    o "Identifier",                             -> [$1]
    o "Identifier , Identifier",                -> [$1, $3]
  ]

  # The source of the array comprehension can optionally be filtered.
  ForSource: [
    o "IN Expression",                          -> {source:   $2}
    o "OF Expression",                          -> {source:   $2, object: true}
    o "ForSource WHEN Expression",              -> $1.filter: $3; $1
    o "ForSource BY Expression",                -> $1.step:   $3; $1
  ]

  # Switch/When blocks.
  Switch: [
    o "SWITCH Expression INDENT Whens OUTDENT", -> $4.rewrite_condition($2)
    o "SWITCH Expression INDENT Whens ELSE Block OUTDENT", -> $4.rewrite_condition($2).add_else($6, true)
  ]

  # The inner list of whens.
  Whens: [
    o "When",                                   -> $1
    o "Whens When",                             -> $1.push $2
  ]

  # An individual when.
  When: [
    o "LEADING_WHEN SimpleArgs Block",          -> new IfNode($2, $3, null, {statement: true})
    o "LEADING_WHEN SimpleArgs Block TERMINATOR", -> new IfNode($2, $3, null, {statement: true})
    o "Comment TERMINATOR When",                -> $3.comment: $1; $3
  ]

  # The most basic form of "if".
  IfStart: [
    o "IF Expression Block",                    -> new IfNode($2, $3)
    o "IfStart ElsIfs",                         -> $1.add_else($2)
  ]

  IfBlock: [
    o "IfStart",                                -> $1
    o "IfStart ELSE Block",                     -> $1.add_else($3)
  ]

  # Multiple elsifs can be chained together.
  ElsIfs: [
    o "ELSE IF Expression Block",               -> (new IfNode($3, $4)).force_statement()
    o "ElsIfs ElsIf",                           -> $1.add_else($2)
  ]

  # The full complement of if blocks, including postfix one-liner ifs and unlesses.
  If: [
    o "IfBlock",                                -> $1
    o "Expression IF Expression",               -> new IfNode($3, Expressions.wrap([$1]), null, {statement: true})
    o "Expression UNLESS Expression",           -> new IfNode($3, Expressions.wrap([$1]), null, {statement: true, invert: true})
  ]

}

# Helpers ==============================================================

# Make the Jison parser.
bnf: {}
tokens: []
for name, non_terminal of grammar
  bnf[name]: for option in non_terminal
    for part in option[0].split(" ")
      if !grammar[part]
        tokens.push(part)
    if name == "Root"
      option[1] = "return " + option[1]
    option
tokens: tokens.join(" ")
exports.parser: new Parser({tokens: tokens, bnf: bnf, operators: operators.reverse(), startSymbol: 'Root'}, {debug: false})
