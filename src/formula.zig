const std = @import("std");
const Allocator = std.mem.Allocator;

/// Formula Engine - Expression parsing and evaluation with variables
///
/// Provides runtime expression evaluation for game balance and scripting:
/// - Expression parsing with operators (+, -, *, /, %, ^)
/// - Variable substitution from named values
/// - Built-in functions (min, max, clamp, abs, floor, ceil, round, sqrt)
/// - Parentheses for grouping
/// - Comparison operators (==, !=, <, >, <=, >=)
/// - Logical operators (and, or, not)
///
/// Example usage:
/// ```zig
/// var formula = FormulaEngine.init(allocator);
/// defer formula.deinit();
///
/// // Set variables
/// formula.setVar("base_damage", 10);
/// formula.setVar("strength", 15);
/// formula.setVar("level", 5);
///
/// // Evaluate expressions
/// const damage = try formula.evaluate("base_damage + strength * 0.5 + level");
/// const clamped = try formula.evaluate("clamp(damage, 5, 100)");
/// const crit = try formula.evaluate("base_damage * 2 if level > 10 else base_damage");
/// ```

/// Maximum variable name length
pub const MAX_VAR_NAME: usize = 63;

/// Maximum formula length
pub const MAX_FORMULA_LENGTH: usize = 1023;

/// Token types for lexer
pub const TokenType = enum {
    number,
    identifier,
    plus,
    minus,
    star,
    slash,
    percent,
    caret,
    lparen,
    rparen,
    comma,
    eq,
    neq,
    lt,
    gt,
    lte,
    gte,
    kw_and,
    kw_or,
    kw_not,
    kw_if,
    kw_else,
    eof,
    invalid,
};

/// Token structure
pub const Token = struct {
    token_type: TokenType,
    start: usize,
    end: usize,
    number_value: f64 = 0,
};

/// Lexer for tokenizing formulas
pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source };
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            return .{ .token_type = .eof, .start = self.pos, .end = self.pos };
        }

        const start = self.pos;
        const c = self.source[self.pos];

        // Numbers
        if (std.ascii.isDigit(c) or (c == '.' and self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))) {
            return self.readNumber(start);
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.readIdentifier(start);
        }

        // Operators
        self.pos += 1;
        switch (c) {
            '+' => return .{ .token_type = .plus, .start = start, .end = self.pos },
            '-' => return .{ .token_type = .minus, .start = start, .end = self.pos },
            '*' => return .{ .token_type = .star, .start = start, .end = self.pos },
            '/' => return .{ .token_type = .slash, .start = start, .end = self.pos },
            '%' => return .{ .token_type = .percent, .start = start, .end = self.pos },
            '^' => return .{ .token_type = .caret, .start = start, .end = self.pos },
            '(' => return .{ .token_type = .lparen, .start = start, .end = self.pos },
            ')' => return .{ .token_type = .rparen, .start = start, .end = self.pos },
            ',' => return .{ .token_type = .comma, .start = start, .end = self.pos },
            '=' => {
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.pos += 1;
                    return .{ .token_type = .eq, .start = start, .end = self.pos };
                }
                return .{ .token_type = .invalid, .start = start, .end = self.pos };
            },
            '!' => {
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.pos += 1;
                    return .{ .token_type = .neq, .start = start, .end = self.pos };
                }
                return .{ .token_type = .invalid, .start = start, .end = self.pos };
            },
            '<' => {
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.pos += 1;
                    return .{ .token_type = .lte, .start = start, .end = self.pos };
                }
                return .{ .token_type = .lt, .start = start, .end = self.pos };
            },
            '>' => {
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.pos += 1;
                    return .{ .token_type = .gte, .start = start, .end = self.pos };
                }
                return .{ .token_type = .gt, .start = start, .end = self.pos };
            },
            else => return .{ .token_type = .invalid, .start = start, .end = self.pos },
        }
    }

    fn readNumber(self: *Lexer, start: usize) Token {
        var has_dot = false;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isDigit(c)) {
                self.pos += 1;
            } else if (c == '.' and !has_dot) {
                has_dot = true;
                self.pos += 1;
            } else {
                break;
            }
        }

        const num_str = self.source[start..self.pos];
        const value = std.fmt.parseFloat(f64, num_str) catch 0;
        return .{
            .token_type = .number,
            .start = start,
            .end = self.pos,
            .number_value = value,
        };
    }

    fn readIdentifier(self: *Lexer, start: usize) Token {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.pos += 1;
            } else {
                break;
            }
        }

        const ident = self.source[start..self.pos];

        // Check for keywords
        const token_type: TokenType = if (std.mem.eql(u8, ident, "and"))
            .kw_and
        else if (std.mem.eql(u8, ident, "or"))
            .kw_or
        else if (std.mem.eql(u8, ident, "not"))
            .kw_not
        else if (std.mem.eql(u8, ident, "if"))
            .kw_if
        else if (std.mem.eql(u8, ident, "else"))
            .kw_else
        else
            .identifier;

        return .{ .token_type = token_type, .start = start, .end = self.pos };
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
        }
    }

    pub fn getTokenText(self: *const Lexer, token: Token) []const u8 {
        return self.source[token.start..token.end];
    }
};

/// Parser and evaluator for formulas
pub const Parser = struct {
    lexer: Lexer,
    current: Token,
    variables: *const std.StringHashMap(f64),

    pub fn init(source: []const u8, variables: *const std.StringHashMap(f64)) Parser {
        var p = Parser{
            .lexer = Lexer.init(source),
            .current = undefined,
            .variables = variables,
        };
        p.current = p.lexer.nextToken();
        return p;
    }

    fn advance(self: *Parser) void {
        self.current = self.lexer.nextToken();
    }

    fn expect(self: *Parser, expected: TokenType) !void {
        if (self.current.token_type != expected) {
            return error.UnexpectedToken;
        }
        self.advance();
    }

    pub fn parse(self: *Parser) !f64 {
        const result = try self.parseConditional();
        if (self.current.token_type != .eof) {
            return error.UnexpectedToken;
        }
        return result;
    }

    // Conditional: expr (if condition else expr)?
    fn parseConditional(self: *Parser) !f64 {
        const result = try self.parseOr();

        if (self.current.token_type == .kw_if) {
            self.advance();
            const condition = try self.parseOr();
            try self.expect(.kw_else);
            const else_value = try self.parseConditional();
            return if (condition != 0) result else else_value;
        }

        return result;
    }

    // Or: and (or and)*
    fn parseOr(self: *Parser) !f64 {
        var result = try self.parseAnd();

        while (self.current.token_type == .kw_or) {
            self.advance();
            const right = try self.parseAnd();
            result = if (result != 0 or right != 0) 1 else 0;
        }

        return result;
    }

    // And: comparison (and comparison)*
    fn parseAnd(self: *Parser) !f64 {
        var result = try self.parseComparison();

        while (self.current.token_type == .kw_and) {
            self.advance();
            const right = try self.parseComparison();
            result = if (result != 0 and right != 0) 1 else 0;
        }

        return result;
    }

    // Comparison: additive ((== | != | < | > | <= | >=) additive)?
    fn parseComparison(self: *Parser) !f64 {
        const left = try self.parseAdditive();

        const result: f64 = switch (self.current.token_type) {
            .eq => blk: {
                self.advance();
                const right = try self.parseAdditive();
                break :blk if (left == right) 1 else 0;
            },
            .neq => blk: {
                self.advance();
                const right = try self.parseAdditive();
                break :blk if (left != right) 1 else 0;
            },
            .lt => blk: {
                self.advance();
                const right = try self.parseAdditive();
                break :blk if (left < right) 1 else 0;
            },
            .gt => blk: {
                self.advance();
                const right = try self.parseAdditive();
                break :blk if (left > right) 1 else 0;
            },
            .lte => blk: {
                self.advance();
                const right = try self.parseAdditive();
                break :blk if (left <= right) 1 else 0;
            },
            .gte => blk: {
                self.advance();
                const right = try self.parseAdditive();
                break :blk if (left >= right) 1 else 0;
            },
            else => left,
        };

        return result;
    }

    // Additive: multiplicative ((+ | -) multiplicative)*
    fn parseAdditive(self: *Parser) !f64 {
        var result = try self.parseMultiplicative();

        while (true) {
            switch (self.current.token_type) {
                .plus => {
                    self.advance();
                    result += try self.parseMultiplicative();
                },
                .minus => {
                    self.advance();
                    result -= try self.parseMultiplicative();
                },
                else => break,
            }
        }

        return result;
    }

    // Multiplicative: power ((* | / | %) power)*
    fn parseMultiplicative(self: *Parser) !f64 {
        var result = try self.parsePower();

        while (true) {
            switch (self.current.token_type) {
                .star => {
                    self.advance();
                    result *= try self.parsePower();
                },
                .slash => {
                    self.advance();
                    const divisor = try self.parsePower();
                    if (divisor == 0) return error.DivisionByZero;
                    result /= divisor;
                },
                .percent => {
                    self.advance();
                    const divisor = try self.parsePower();
                    if (divisor == 0) return error.DivisionByZero;
                    result = @mod(result, divisor);
                },
                else => break,
            }
        }

        return result;
    }

    // Power: unary (^ power)?
    fn parsePower(self: *Parser) !f64 {
        const base = try self.parseUnary();

        if (self.current.token_type == .caret) {
            self.advance();
            const exp = try self.parsePower(); // Right associative
            return std.math.pow(f64, base, exp);
        }

        return base;
    }

    // Unary: (- | not)? primary
    fn parseUnary(self: *Parser) !f64 {
        if (self.current.token_type == .minus) {
            self.advance();
            return -try self.parseUnary();
        }

        if (self.current.token_type == .kw_not) {
            self.advance();
            const val = try self.parseUnary();
            return if (val == 0) 1 else 0;
        }

        return self.parsePrimary();
    }

    // Primary: number | identifier | function_call | (expr)
    fn parsePrimary(self: *Parser) !f64 {
        switch (self.current.token_type) {
            .number => {
                const val = self.current.number_value;
                self.advance();
                return val;
            },
            .identifier => {
                const name = self.lexer.getTokenText(self.current);
                self.advance();

                // Check if function call
                if (self.current.token_type == .lparen) {
                    return self.parseFunction(name);
                }

                // Variable lookup
                return self.variables.get(name) orelse error.UndefinedVariable;
            },
            .lparen => {
                self.advance();
                const result = try self.parseConditional();
                try self.expect(.rparen);
                return result;
            },
            else => return error.UnexpectedToken,
        }
    }

    // Function call: identifier(arg, arg, ...)
    fn parseFunction(self: *Parser, name: []const u8) !f64 {
        try self.expect(.lparen);

        var args: [8]f64 = undefined;
        var arg_count: usize = 0;

        if (self.current.token_type != .rparen) {
            args[arg_count] = try self.parseConditional();
            arg_count += 1;

            while (self.current.token_type == .comma) {
                self.advance();
                if (arg_count >= 8) return error.TooManyArguments;
                args[arg_count] = try self.parseConditional();
                arg_count += 1;
            }
        }

        try self.expect(.rparen);

        return evaluateFunction(name, args[0..arg_count]);
    }
};

/// Evaluate a built-in function
fn evaluateFunction(name: []const u8, args: []const f64) !f64 {
    if (std.mem.eql(u8, name, "min")) {
        if (args.len < 2) return error.NotEnoughArguments;
        return @min(args[0], args[1]);
    }

    if (std.mem.eql(u8, name, "max")) {
        if (args.len < 2) return error.NotEnoughArguments;
        return @max(args[0], args[1]);
    }

    if (std.mem.eql(u8, name, "clamp")) {
        if (args.len < 3) return error.NotEnoughArguments;
        return @max(args[1], @min(args[0], args[2]));
    }

    if (std.mem.eql(u8, name, "abs")) {
        if (args.len < 1) return error.NotEnoughArguments;
        return @abs(args[0]);
    }

    if (std.mem.eql(u8, name, "floor")) {
        if (args.len < 1) return error.NotEnoughArguments;
        return @floor(args[0]);
    }

    if (std.mem.eql(u8, name, "ceil")) {
        if (args.len < 1) return error.NotEnoughArguments;
        return @ceil(args[0]);
    }

    if (std.mem.eql(u8, name, "round")) {
        if (args.len < 1) return error.NotEnoughArguments;
        return @round(args[0]);
    }

    if (std.mem.eql(u8, name, "sqrt")) {
        if (args.len < 1) return error.NotEnoughArguments;
        if (args[0] < 0) return error.InvalidArgument;
        return @sqrt(args[0]);
    }

    if (std.mem.eql(u8, name, "pow")) {
        if (args.len < 2) return error.NotEnoughArguments;
        return std.math.pow(f64, args[0], args[1]);
    }

    if (std.mem.eql(u8, name, "sin")) {
        if (args.len < 1) return error.NotEnoughArguments;
        return @sin(args[0]);
    }

    if (std.mem.eql(u8, name, "cos")) {
        if (args.len < 1) return error.NotEnoughArguments;
        return @cos(args[0]);
    }

    if (std.mem.eql(u8, name, "tan")) {
        if (args.len < 1) return error.NotEnoughArguments;
        return @tan(args[0]);
    }

    if (std.mem.eql(u8, name, "log")) {
        if (args.len < 1) return error.NotEnoughArguments;
        if (args[0] <= 0) return error.InvalidArgument;
        return @log(args[0]);
    }

    if (std.mem.eql(u8, name, "log10")) {
        if (args.len < 1) return error.NotEnoughArguments;
        if (args[0] <= 0) return error.InvalidArgument;
        return @log10(args[0]);
    }

    if (std.mem.eql(u8, name, "exp")) {
        if (args.len < 1) return error.NotEnoughArguments;
        return @exp(args[0]);
    }

    if (std.mem.eql(u8, name, "lerp")) {
        if (args.len < 3) return error.NotEnoughArguments;
        return args[0] + (args[1] - args[0]) * args[2];
    }

    if (std.mem.eql(u8, name, "sign")) {
        if (args.len < 1) return error.NotEnoughArguments;
        if (args[0] > 0) return 1;
        if (args[0] < 0) return -1;
        return 0;
    }

    return error.UnknownFunction;
}

/// Formula evaluation result
pub const EvalResult = struct {
    value: f64,
    error_msg: ?[]const u8 = null,
};

/// Formula Engine - main interface for expression evaluation
pub const FormulaEngine = struct {
    allocator: Allocator,
    variables: std.StringHashMap(f64),

    pub fn init(allocator: Allocator) FormulaEngine {
        return .{
            .allocator = allocator,
            .variables = std.StringHashMap(f64).init(allocator),
        };
    }

    pub fn deinit(self: *FormulaEngine) void {
        var iter = self.variables.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.variables.deinit();
    }

    /// Set a variable value
    pub fn setVar(self: *FormulaEngine, name: []const u8, value: f64) void {
        if (self.variables.getKey(name)) |existing_key| {
            self.variables.put(existing_key, value) catch {};
        } else {
            const owned_name = self.allocator.dupe(u8, name) catch return;
            self.variables.put(owned_name, value) catch {
                self.allocator.free(owned_name);
            };
        }
    }

    /// Get a variable value
    pub fn getVar(self: *const FormulaEngine, name: []const u8) ?f64 {
        return self.variables.get(name);
    }

    /// Remove a variable
    pub fn removeVar(self: *FormulaEngine, name: []const u8) bool {
        if (self.variables.fetchRemove(name)) |kv| {
            self.allocator.free(kv.key);
            return true;
        }
        return false;
    }

    /// Clear all variables
    pub fn clearVars(self: *FormulaEngine) void {
        var iter = self.variables.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.variables.clearRetainingCapacity();
    }

    /// Get variable count
    pub fn getVarCount(self: *const FormulaEngine) usize {
        return self.variables.count();
    }

    /// Evaluate a formula expression
    pub fn evaluate(self: *const FormulaEngine, formula: []const u8) !f64 {
        var parser = Parser.init(formula, &self.variables);
        return parser.parse();
    }

    /// Evaluate a formula, returning default on error
    pub fn evaluateOr(self: *const FormulaEngine, formula: []const u8, default: f64) f64 {
        return self.evaluate(formula) catch default;
    }

    /// Evaluate a formula as boolean (non-zero = true)
    pub fn evaluateBool(self: *const FormulaEngine, formula: []const u8) !bool {
        const result = try self.evaluate(formula);
        return result != 0;
    }

    /// Evaluate a formula as integer
    pub fn evaluateInt(self: *const FormulaEngine, formula: []const u8) !i64 {
        const result = try self.evaluate(formula);
        return @intFromFloat(result);
    }

    /// Evaluate with temporary variable bindings
    pub fn evaluateWith(self: *FormulaEngine, formula: []const u8, bindings: []const struct { []const u8, f64 }) !f64 {
        // Save original values
        var saved = std.ArrayList(struct { []const u8, ?f64 }).init(self.allocator);
        defer saved.deinit();

        for (bindings) |binding| {
            try saved.append(.{ binding[0], self.variables.get(binding[0]) });
            self.setVar(binding[0], binding[1]);
        }

        const result = self.evaluate(formula);

        // Restore original values
        for (saved.items) |s| {
            if (s[1]) |val| {
                self.setVar(s[0], val);
            } else {
                _ = self.removeVar(s[0]);
            }
        }

        return result;
    }

    /// Get all variable names
    pub fn getVarNames(self: *const FormulaEngine, allocator: Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.variables.count());
        var i: usize = 0;
        var iter = self.variables.keyIterator();
        while (iter.next()) |key| {
            names[i] = key.*;
            i += 1;
        }
        return names;
    }
};

/// Pre-compiled formula for repeated evaluation
pub const CompiledFormula = struct {
    source: []const u8,
    allocator: Allocator,
    owned: bool,

    pub fn compile(allocator: Allocator, formula: []const u8) !CompiledFormula {
        // Validate syntax by parsing once
        var empty_vars = std.StringHashMap(f64).init(allocator);
        defer empty_vars.deinit();

        var parser = Parser.init(formula, &empty_vars);
        _ = parser.parse() catch |err| switch (err) {
            error.UndefinedVariable => {}, // Expected for validation
            else => return err,
        };

        const owned_source = try allocator.dupe(u8, formula);
        return .{
            .source = owned_source,
            .allocator = allocator,
            .owned = true,
        };
    }

    pub fn deinit(self: *CompiledFormula) void {
        if (self.owned) {
            self.allocator.free(@constCast(self.source));
        }
    }

    pub fn evaluate(self: *const CompiledFormula, engine: *const FormulaEngine) !f64 {
        return engine.evaluate(self.source);
    }
};

// ============================================================
// Tests
// ============================================================

test "FormulaEngine: basic arithmetic" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 7), try engine.evaluate("3 + 4"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 10), try engine.evaluate("15 - 5"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 20), try engine.evaluate("4 * 5"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3), try engine.evaluate("15 / 5"), 0.001);
}

test "FormulaEngine: operator precedence" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 14), try engine.evaluate("2 + 3 * 4"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 20), try engine.evaluate("(2 + 3) * 4"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 11), try engine.evaluate("2 + 3 ^ 2"), 0.001);
}

test "FormulaEngine: variables" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    engine.setVar("x", 10);
    engine.setVar("y", 5);

    try std.testing.expectApproxEqAbs(@as(f64, 15), try engine.evaluate("x + y"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 50), try engine.evaluate("x * y"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 25), try engine.evaluate("x + y * 3"), 0.001);
}

test "FormulaEngine: functions" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 3), try engine.evaluate("min(5, 3)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 5), try engine.evaluate("max(5, 3)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 5), try engine.evaluate("clamp(10, 0, 5)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("clamp(-5, 0, 10)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 5), try engine.evaluate("abs(-5)"), 0.001);
}

test "FormulaEngine: math functions" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 3), try engine.evaluate("floor(3.7)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 4), try engine.evaluate("ceil(3.2)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 4), try engine.evaluate("round(3.5)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3), try engine.evaluate("sqrt(9)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 8), try engine.evaluate("pow(2, 3)"), 0.001);
}

test "FormulaEngine: comparison operators" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("5 > 3"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("5 < 3"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("5 == 5"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("5 != 3"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("5 >= 5"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("3 <= 5"), 0.001);
}

test "FormulaEngine: logical operators" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("1 and 1"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("1 and 0"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("1 or 0"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("0 or 0"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("not 1"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("not 0"), 0.001);
}

test "FormulaEngine: conditional expressions" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    engine.setVar("level", 15);

    try std.testing.expectApproxEqAbs(@as(f64, 100), try engine.evaluate("100 if level > 10 else 50"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 50), try engine.evaluate("100 if level > 20 else 50"), 0.001);
}

test "FormulaEngine: complex expressions" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    engine.setVar("base_damage", 10);
    engine.setVar("strength", 15);
    engine.setVar("level", 5);

    // RPG damage formula
    const damage = try engine.evaluate("base_damage + strength * 0.5 + level * 2");
    try std.testing.expectApproxEqAbs(@as(f64, 27.5), damage, 0.001);

    // Clamped result
    const clamped = try engine.evaluate("clamp(base_damage * 3, 10, 25)");
    try std.testing.expectApproxEqAbs(@as(f64, 25), clamped, 0.001);
}

test "FormulaEngine: unary minus" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, -5), try engine.evaluate("-5"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, -7), try engine.evaluate("-3 - 4"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 7), try engine.evaluate("3 - -4"), 0.001);
}

test "FormulaEngine: modulo" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("7 % 3"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("9 % 3"), 0.001);
}

test "FormulaEngine: power operator" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 8), try engine.evaluate("2 ^ 3"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 512), try engine.evaluate("2 ^ 3 ^ 2"), 0.001); // Right associative: 2^(3^2) = 2^9
}

test "FormulaEngine: division by zero" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectError(error.DivisionByZero, engine.evaluate("5 / 0"));
    try std.testing.expectError(error.DivisionByZero, engine.evaluate("5 % 0"));
}

test "FormulaEngine: undefined variable" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectError(error.UndefinedVariable, engine.evaluate("undefined_var + 5"));
}

test "FormulaEngine: evaluateOr default" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 10), engine.evaluateOr("5 + 5", 0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 42), engine.evaluateOr("undefined", 42), 0.001);
}

test "FormulaEngine: evaluateBool" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expect(try engine.evaluateBool("5 > 3"));
    try std.testing.expect(!try engine.evaluateBool("3 > 5"));
    try std.testing.expect(try engine.evaluateBool("1"));
    try std.testing.expect(!try engine.evaluateBool("0"));
}

test "FormulaEngine: evaluateInt" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectEqual(@as(i64, 7), try engine.evaluateInt("3.5 + 3.5"));
    try std.testing.expectEqual(@as(i64, 10), try engine.evaluateInt("10.9"));
}

test "FormulaEngine: variable management" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    engine.setVar("test", 42);
    try std.testing.expectApproxEqAbs(@as(f64, 42), engine.getVar("test").?, 0.001);
    try std.testing.expectEqual(@as(usize, 1), engine.getVarCount());

    engine.setVar("test", 100); // Update
    try std.testing.expectApproxEqAbs(@as(f64, 100), engine.getVar("test").?, 0.001);
    try std.testing.expectEqual(@as(usize, 1), engine.getVarCount());

    try std.testing.expect(engine.removeVar("test"));
    try std.testing.expect(engine.getVar("test") == null);

    engine.setVar("a", 1);
    engine.setVar("b", 2);
    engine.clearVars();
    try std.testing.expectEqual(@as(usize, 0), engine.getVarCount());
}

test "FormulaEngine: lerp function" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("lerp(0, 10, 0)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 5), try engine.evaluate("lerp(0, 10, 0.5)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 10), try engine.evaluate("lerp(0, 10, 1)"), 0.001);
}

test "FormulaEngine: sign function" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("sign(5)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, -1), try engine.evaluate("sign(-5)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("sign(0)"), 0.001);
}

test "FormulaEngine: nested functions" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 5), try engine.evaluate("max(min(10, 5), 3)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 4), try engine.evaluate("floor(sqrt(20))"), 0.001);
}

test "CompiledFormula: basic usage" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    var formula = try CompiledFormula.compile(allocator, "x * 2 + y");
    defer formula.deinit();

    engine.setVar("x", 5);
    engine.setVar("y", 3);
    try std.testing.expectApproxEqAbs(@as(f64, 13), try formula.evaluate(&engine), 0.001);

    engine.setVar("x", 10);
    try std.testing.expectApproxEqAbs(@as(f64, 23), try formula.evaluate(&engine), 0.001);
}

test "FormulaEngine: trig functions" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("sin(0)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("cos(0)"), 0.001);
}

test "FormulaEngine: log and exp" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 1), try engine.evaluate("exp(0)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), try engine.evaluate("log(1)"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 2), try engine.evaluate("log10(100)"), 0.001);
}

test "FormulaEngine: floating point numbers" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 3.14), try engine.evaluate("3.14"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), try engine.evaluate(".5"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 6.28), try engine.evaluate("3.14 * 2"), 0.001);
}

test "FormulaEngine: getVarNames" {
    const allocator = std.testing.allocator;
    var engine = FormulaEngine.init(allocator);
    defer engine.deinit();

    engine.setVar("alpha", 1);
    engine.setVar("beta", 2);
    engine.setVar("gamma", 3);

    const names = try engine.getVarNames(allocator);
    defer allocator.free(names);

    try std.testing.expectEqual(@as(usize, 3), names.len);
}
