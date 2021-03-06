(function(){
  var ACCESSORS, ASSIGNMENT, BEFORE_WHEN, CALLABLE, CODE, COFFEE_KEYWORDS, COMMENT, COMMENT_CLEANER, HEREDOC, HEREDOC_INDENT, IDENTIFIER, JS, JS_CLEANER, JS_FORBIDDEN, JS_KEYWORDS, KEYWORDS, LAST_DENT, LAST_DENTS, Lexer, MULTILINER, MULTI_DENT, NOT_REGEX, NO_NEWLINE, NUMBER, OPERATOR, REGEX, RESERVED, Rewriter, STRING, STRING_NEWLINES, WHITESPACE;
  if ((typeof process !== "undefined" && process !== null)) {
    Rewriter = require('./rewriter').Rewriter;
  } else {
    this.exports = this;
    Rewriter = this.Rewriter;
  }
  // Constants ============================================================
  // Keywords that CoffeScript shares in common with JS.
  JS_KEYWORDS = ["if", "else", "true", "false", "new", "return", "try", "catch", "finally", "throw", "break", "continue", "for", "in", "while", "delete", "instanceof", "typeof", "switch", "super", "extends", "class"];
  // CoffeeScript-only keywords -- which we're more relaxed about allowing.
  COFFEE_KEYWORDS = ["then", "unless", "yes", "no", "on", "off", "and", "or", "is", "isnt", "not", "of", "by", "where", "when"];
  // The list of keywords passed verbatim to the parser.
  KEYWORDS = JS_KEYWORDS.concat(COFFEE_KEYWORDS);
  // The list of keywords that are reserved by JavaScript, but not used, or are
  // used by CoffeeScript internally. Using these will throw an error.
  RESERVED = ["case", "default", "do", "function", "var", "void", "with", "const", "let", "debugger", "enum", "export", "import", "native", "__extends", "__hasProp"];
  // JavaScript keywords and reserved words together, excluding CoffeeScript ones.
  JS_FORBIDDEN = JS_KEYWORDS.concat(RESERVED);
  // Token matching regexes. (keep the IDENTIFIER regex in sync with AssignNode.)
  IDENTIFIER = /^([a-zA-Z$_](\w|\$)*)/;
  NUMBER = /^(\b((0(x|X)[0-9a-fA-F]+)|([0-9]+(\.[0-9]+)?(e[+\-]?[0-9]+)?)))\b/i;
  STRING = /^(""|''|"([\s\S]*?)([^\\]|\\\\)"|'([\s\S]*?)([^\\]|\\\\)')/;
  HEREDOC = /^("{6}|'{6}|"{3}\n?([\s\S]*?)\n?([ \t]*)"{3}|'{3}\n?([\s\S]*?)\n?([ \t]*)'{3})/;
  JS = /^(``|`([\s\S]*?)([^\\]|\\\\)`)/;
  OPERATOR = /^([+\*&|\/\-%=<>:!?]+)/;
  WHITESPACE = /^([ \t]+)/;
  COMMENT = /^(((\n?[ \t]*)?#[^\n]*)+)/;
  CODE = /^((-|=)>)/;
  REGEX = /^(\/(\S.*?)?([^\\]|\\\\)\/[imgy]{0,4})/;
  MULTI_DENT = /^((\n([ \t]*))+)(\.)?/;
  LAST_DENTS = /\n([ \t]*)/g;
  LAST_DENT = /\n([ \t]*)/;
  ASSIGNMENT = /^(:|=)$/;
  // Token cleaning regexes.
  JS_CLEANER = /(^`|`$)/g;
  MULTILINER = /\n/g;
  STRING_NEWLINES = /\n[ \t]*/g;
  COMMENT_CLEANER = /(^[ \t]*#|\n[ \t]*$)/mg;
  NO_NEWLINE = /^([+\*&|\/\-%=<>:!.\\][<>=&|]*|and|or|is|isnt|not|delete|typeof|instanceof)$/;
  HEREDOC_INDENT = /^[ \t]+/mg;
  // Tokens which a regular expression will never immediately follow, but which
  // a division operator might.
  // See: http://www.mozilla.org/js/language/js20-2002-04/rationale/syntax.html#regular-expressions
  // Our list is shorter, due to sans-parentheses method calls.
  NOT_REGEX = ['NUMBER', 'REGEX', '++', '--', 'FALSE', 'NULL', 'TRUE'];
  // Tokens which could legitimately be invoked or indexed.
  CALLABLE = ['IDENTIFIER', 'SUPER', ')', ']', '}', 'STRING', '@'];
  // Tokens that indicate an access -- keywords immediately following will be
  // treated as identifiers.
  ACCESSORS = ['PROPERTY_ACCESS', 'PROTOTYPE_ACCESS', 'SOAK_ACCESS', '@'];
  // Tokens that, when immediately preceding a 'WHEN', indicate that its leading.
  BEFORE_WHEN = ['INDENT', 'OUTDENT', 'TERMINATOR'];
  // The lexer reads a stream of CoffeeScript and divvys it up into tagged
  // tokens. A minor bit of the ambiguity in the grammar has been avoided by
  // pushing some extra smarts into the Lexer.
  exports.Lexer = (function() {
    Lexer = function Lexer() {    };
    // Scan by attempting to match tokens one character at a time. Slow and steady.
    Lexer.prototype.tokenize = function tokenize(code) {
      this.code = code;
      // Cleanup code by remove extra line breaks, TODO: chomp
      this.i = 0;
      // Current character position we're parsing
      this.line = 1;
      // The current line.
      this.indent = 0;
      // The current indent level.
      this.indents = [];
      // The stack of all indent levels we are currently within.
      this.tokens = [];
      // Collection of all parsed tokens in the form [:TOKEN_TYPE, value]
      while (this.i < this.code.length) {
        this.chunk = this.code.slice(this.i);
        this.extract_next_token();
      }
      this.close_indentation();
      return (new Rewriter()).rewrite(this.tokens);
    };
    // At every position, run through this list of attempted matches,
    // short-circuiting if any of them succeed.
    Lexer.prototype.extract_next_token = function extract_next_token() {
      if (this.identifier_token()) {
        return null;
      }
      if (this.number_token()) {
        return null;
      }
      if (this.heredoc_token()) {
        return null;
      }
      if (this.string_token()) {
        return null;
      }
      if (this.js_token()) {
        return null;
      }
      if (this.regex_token()) {
        return null;
      }
      if (this.indent_token()) {
        return null;
      }
      if (this.comment_token()) {
        return null;
      }
      if (this.whitespace_token()) {
        return null;
      }
      return this.literal_token();
    };
    // Tokenizers ==========================================================
    // Matches identifying literals: variables, keywords, method names, etc.
    Lexer.prototype.identifier_token = function identifier_token() {
      var id, tag;
      if (!((id = this.match(IDENTIFIER, 1)))) {
        return false;
      }
      if (this.value() === '::') {
        this.tag(1, 'PROTOTYPE_ACCESS');
      }
      if (this.value() === '.' && !(this.value(2) === '.')) {
        if (this.tag(2) === '?') {
          this.tag(1, 'SOAK_ACCESS');
          this.tokens.splice(-2, 1);
        } else {
          this.tag(1, 'PROPERTY_ACCESS');
        }
      }
      tag = 'IDENTIFIER';
      if (KEYWORDS.indexOf(id) >= 0 && !((ACCESSORS.indexOf(this.tag()) >= 0) && !this.prev().spaced)) {
        tag = id.toUpperCase();
      }
      if (RESERVED.indexOf(id) >= 0) {
        throw new Error('SyntaxError: Reserved word "' + id + '" on line ' + this.line);
      }
      if (tag === 'WHEN' && BEFORE_WHEN.indexOf(this.tag()) >= 0) {
        tag = 'LEADING_WHEN';
      }
      this.token(tag, id);
      this.i += id.length;
      return true;
    };
    // Matches numbers, including decimals, hex, and exponential notation.
    Lexer.prototype.number_token = function number_token() {
      var number;
      if (!((number = this.match(NUMBER, 1)))) {
        return false;
      }
      this.token('NUMBER', number);
      this.i += number.length;
      return true;
    };
    // Matches strings, including multi-line strings.
    Lexer.prototype.string_token = function string_token() {
      var escaped, string;
      if (!((string = this.match(STRING, 1)))) {
        return false;
      }
      escaped = string.replace(STRING_NEWLINES, " \\\n");
      this.token('STRING', escaped);
      this.line += this.count(string, "\n");
      this.i += string.length;
      return true;
    };
    // Matches heredocs, adjusting indentation to the correct level.
    Lexer.prototype.heredoc_token = function heredoc_token() {
      var doc, indent, match;
      if (!((match = this.chunk.match(HEREDOC)))) {
        return false;
      }
      doc = match[2] || match[4];
      indent = (doc.match(HEREDOC_INDENT) || ['']).sort()[0];
      doc = doc.replace(new RegExp("^" + indent, 'gm'), '').replace(MULTILINER, "\\n").replace('"', '\\"');
      this.token('STRING', '"' + doc + '"');
      this.line += this.count(match[1], "\n");
      this.i += match[1].length;
      return true;
    };
    // Matches interpolated JavaScript.
    Lexer.prototype.js_token = function js_token() {
      var script;
      if (!((script = this.match(JS, 1)))) {
        return false;
      }
      this.token('JS', script.replace(JS_CLEANER, ''));
      this.i += script.length;
      return true;
    };
    // Matches regular expression literals.
    Lexer.prototype.regex_token = function regex_token() {
      var regex;
      if (!((regex = this.match(REGEX, 1)))) {
        return false;
      }
      if (NOT_REGEX.indexOf(this.tag()) >= 0) {
        return false;
      }
      this.token('REGEX', regex);
      this.i += regex.length;
      return true;
    };
    // Matches and conumes comments.
    Lexer.prototype.comment_token = function comment_token() {
      var comment;
      if (!((comment = this.match(COMMENT, 1)))) {
        return false;
      }
      this.line += (comment.match(MULTILINER) || []).length;
      this.token('COMMENT', comment.replace(COMMENT_CLEANER, '').split(MULTILINER));
      this.token('TERMINATOR', "\n");
      this.i += comment.length;
      return true;
    };
    // Record tokens for indentation differing from the previous line.
    Lexer.prototype.indent_token = function indent_token() {
      var diff, indent, next_character, no_newlines, prev, size;
      if (!((indent = this.match(MULTI_DENT, 1)))) {
        return false;
      }
      this.line += indent.match(MULTILINER).length;
      this.i += indent.length;
      next_character = this.chunk.match(MULTI_DENT)[4];
      prev = this.prev(2);
      no_newlines = next_character === '.' || (this.value() && this.value().match(NO_NEWLINE) && prev && (prev[0] !== '.') && !this.value().match(CODE));
      if (no_newlines) {
        return this.suppress_newlines(indent);
      }
      size = indent.match(LAST_DENTS).reverse()[0].match(LAST_DENT)[1].length;
      if (size === this.indent) {
        return this.newline_token(indent);
      }
      if (size > this.indent) {
        diff = size - this.indent;
        this.token('INDENT', diff);
        this.indents.push(diff);
      } else {
        this.outdent_token(this.indent - size);
      }
      this.indent = size;
      return true;
    };
    // Record an oudent token or tokens, if we're moving back inwards past
    // multiple recorded indents.
    Lexer.prototype.outdent_token = function outdent_token(move_out) {
      var last_indent;
      while (move_out > 0 && this.indents.length) {
        last_indent = this.indents.pop();
        this.token('OUTDENT', last_indent);
        move_out -= last_indent;
      }
      if (!(this.tag() === 'TERMINATOR')) {
        this.token('TERMINATOR', "\n");
      }
      return true;
    };
    // Matches and consumes non-meaningful whitespace.
    Lexer.prototype.whitespace_token = function whitespace_token() {
      var prev, space;
      if (!((space = this.match(WHITESPACE, 1)))) {
        return false;
      }
      prev = this.prev();
      if (prev) {
        prev.spaced = true;
      }
      this.i += space.length;
      return true;
    };
    // Multiple newlines get merged together.
    // Use a trailing \ to escape newlines.
    Lexer.prototype.newline_token = function newline_token(newlines) {
      if (!(this.tag() === 'TERMINATOR')) {
        this.token('TERMINATOR', "\n");
      }
      return true;
    };
    // Tokens to explicitly escape newlines are removed once their job is done.
    Lexer.prototype.suppress_newlines = function suppress_newlines(newlines) {
      if (this.value() === "\\") {
        this.tokens.pop();
      }
      return true;
    };
    // We treat all other single characters as a token. Eg.: ( ) , . !
    // Multi-character operators are also literal tokens, so that Racc can assign
    // the proper order of operations.
    Lexer.prototype.literal_token = function literal_token() {
      var match, not_spaced, tag, value;
      match = this.chunk.match(OPERATOR);
      value = match && match[1];
      if (value && value.match(CODE)) {
        this.tag_parameters();
      }
      value = value || this.chunk.substr(0, 1);
      not_spaced = !this.prev() || !this.prev().spaced;
      tag = value;
      if (value.match(ASSIGNMENT)) {
        tag = 'ASSIGN';
        if (JS_FORBIDDEN.indexOf(this.value()) >= 0) {
          throw new Error('SyntaxError: Reserved word "' + this.value() + '" on line ' + this.line + ' can\'t be assigned');
        }
      } else if (value === ';') {
        tag = 'TERMINATOR';
      } else if (value === '[' && this.tag() === '?' && not_spaced) {
        tag = 'SOAKED_INDEX_START';
        this.soaked_index = true;
        this.tokens.pop();
      } else if (value === ']' && this.soaked_index) {
        tag = 'SOAKED_INDEX_END';
        this.soaked_index = false;
      } else if (CALLABLE.indexOf(this.tag()) >= 0 && not_spaced) {
        if (value === '(') {
          tag = 'CALL_START';
        }
        if (value === '[') {
          tag = 'INDEX_START';
        }
      }
      this.token(tag, value);
      this.i += value.length;
      return true;
    };
    // Helpers =============================================================
    // Add a token to the results, taking note of the line number.
    Lexer.prototype.token = function token(tag, value) {
      return this.tokens.push([tag, value, this.line]);
    };
    // Look at a tag in the current token stream.
    Lexer.prototype.tag = function tag(index, tag) {
      var tok;
      if (!((tok = this.prev(index)))) {
        return null;
      }
      if ((typeof tag !== "undefined" && tag !== null)) {
        return (tok[0] = tag);
      }
      return tok[0];
    };
    // Look at a value in the current token stream.
    Lexer.prototype.value = function value(index, val) {
      var tok;
      if (!((tok = this.prev(index)))) {
        return null;
      }
      if ((typeof val !== "undefined" && val !== null)) {
        return (tok[1] = val);
      }
      return tok[1];
    };
    // Look at a previous token.
    Lexer.prototype.prev = function prev(index) {
      return this.tokens[this.tokens.length - (index || 1)];
    };
    // Count the occurences of a character in a string.
    Lexer.prototype.count = function count(string, letter) {
      var num, pos;
      num = 0;
      pos = string.indexOf(letter);
      while (pos !== -1) {
        num += 1;
        pos = string.indexOf(letter, pos + 1);
      }
      return num;
    };
    // Attempt to match a string against the current chunk, returning the indexed
    // match.
    Lexer.prototype.match = function match(regex, index) {
      var m;
      if (!((m = this.chunk.match(regex)))) {
        return false;
      }
      return m ? m[index] : false;
    };
    // A source of ambiguity in our grammar was parameter lists in function
    // definitions (as opposed to argument lists in function calls). Tag
    // parameter identifiers in order to avoid this. Also, parameter lists can
    // make use of splats.
    Lexer.prototype.tag_parameters = function tag_parameters() {
      var _a, i, tok;
      if (this.tag() !== ')') {
        return null;
      }
      i = 0;
      while (true) {
        i += 1;
        tok = this.prev(i);
        if (!tok) {
          return null;
        }
        if ((_a = tok[0]) === 'IDENTIFIER') {
          tok[0] = 'PARAM';
        } else if (_a === ')') {
          tok[0] = 'PARAM_END';
        } else if (_a === '(') {
          return (tok[0] = 'PARAM_START');
        }
      }
      return true;
    };
    // Close up all remaining open blocks. IF the first token is an indent,
    // axe it.
    Lexer.prototype.close_indentation = function close_indentation() {
      return this.outdent_token(this.indent);
    };
    return Lexer;
  }).call(this);
})();
