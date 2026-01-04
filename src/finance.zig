//! Finance System - Economic Management
//!
//! A comprehensive financial management system for games with economies.
//! Tracks income, expenses, budgets, and generates per-turn financial reports.
//!
//! Features:
//! - Income/expense tracking with categories
//! - Budget allocation and enforcement
//! - Per-turn financial reports with detailed breakdowns
//! - Deficit handling with configurable policies
//! - Historical financial data for graphs and analysis
//! - Integration with TurnManager for turn-based processing
//! - Treasury management with reserve thresholds
//!
//! Usage:
//! ```zig
//! const Category = enum { military, research, infrastructure, trade };
//!
//! var finance = FinanceManager(Category).init(allocator);
//! defer finance.deinit();
//!
//! // Record transactions
//! try finance.recordIncome(.trade, 1000, "Export revenue");
//! try finance.recordExpense(.military, 500, "Unit upkeep");
//!
//! // Set budgets
//! try finance.setBudget(.military, .{ .allocated = 2000, .priority = 1 });
//!
//! // End turn and get report
//! const report = try finance.endTurn();
//! ```

const std = @import("std");

const log = std.log.scoped(.finance);

/// Policy for handling budget deficits
pub const DeficitPolicy = enum {
    /// Allow spending beyond budget (creates debt)
    allow_debt,
    /// Reject transactions that exceed budget
    reject,
    /// Draw from reserves/treasury to cover deficit
    use_reserves,
    /// Proportionally reduce all expenses
    proportional_cut,
    /// Cut lowest priority expenses first
    priority_cut,
};

/// Policy for handling treasury deficits (negative balance)
pub const TreasuryPolicy = enum {
    /// Allow negative treasury (debt accumulates)
    allow_negative,
    /// Block all expenses when treasury is empty
    block_expenses,
    /// Allow expenses but trigger warnings
    warn_only,
    /// Take emergency loan (automatic debt with interest)
    emergency_loan,
};

/// Configuration for the finance manager
pub const FinanceConfig = struct {
    /// How to handle budget overruns
    deficit_policy: DeficitPolicy = .allow_debt,
    /// How to handle empty treasury
    treasury_policy: TreasuryPolicy = .warn_only,
    /// Interest rate for debt (per turn, as decimal e.g. 0.05 = 5%)
    debt_interest_rate: f64 = 0.05,
    /// Minimum treasury reserve (warning threshold)
    reserve_threshold: f64 = 0,
    /// Maximum debt allowed (0 = unlimited)
    max_debt: f64 = 0,
    /// History size for reports
    history_size: usize = 100,
    /// Enable detailed transaction logging
    detailed_logging: bool = true,
};

/// Type of financial transaction
pub const TransactionType = enum {
    income,
    expense,
    transfer,
    adjustment,
    interest,
    loan,
    repayment,
};

/// A single financial transaction
pub fn Transaction(comptime CategoryType: type) type {
    return struct {
        /// Transaction type
        transaction_type: TransactionType,
        /// Category of the transaction
        category: CategoryType,
        /// Amount (positive for income, negative stored as positive for expenses)
        amount: f64,
        /// Turn when transaction occurred
        turn: u32,
        /// Description/reason for the transaction
        description: []const u8,
        /// Whether this was a budget-approved expense
        budget_approved: bool = true,
    };
}

/// Budget allocation for a category
pub const BudgetAllocation = struct {
    /// Allocated amount for this turn
    allocated: f64 = 0,
    /// Minimum required spending (mandatory expenses)
    minimum: f64 = 0,
    /// Maximum allowed spending (hard cap)
    maximum: f64 = std.math.inf(f64),
    /// Priority for cuts (lower = cut first)
    priority: u8 = 100,
    /// Whether budget can rollover to next turn
    rollover: bool = false,
    /// Rollover percentage (0.0-1.0)
    rollover_percent: f64 = 0,
};

/// Summary of a category's finances for a turn
pub fn CategorySummary(comptime CategoryType: type) type {
    _ = CategoryType;
    return struct {
        /// Total income in this category
        income: f64 = 0,
        /// Total expenses in this category
        expenses: f64 = 0,
        /// Net change (income - expenses)
        net: f64 = 0,
        /// Budget allocated
        budget_allocated: f64 = 0,
        /// Budget remaining
        budget_remaining: f64 = 0,
        /// Budget utilization percentage
        budget_utilization: f64 = 0,
        /// Number of transactions
        transaction_count: u32 = 0,
        /// Whether budget was exceeded
        over_budget: bool = false,
    };
}

/// Per-turn financial report
pub fn FinancialReport(comptime CategoryType: type) type {
    const category_info = @typeInfo(CategoryType);
    const field_count = category_info.@"enum".fields.len;

    return struct {
        const Self = @This();

        /// Turn number
        turn: u32,
        /// Total income across all categories
        total_income: f64 = 0,
        /// Total expenses across all categories
        total_expenses: f64 = 0,
        /// Net change (income - expenses)
        net_change: f64 = 0,
        /// Starting treasury balance
        starting_balance: f64 = 0,
        /// Ending treasury balance
        ending_balance: f64 = 0,
        /// Current debt level
        debt: f64 = 0,
        /// Interest paid this turn
        interest_paid: f64 = 0,
        /// Per-category summaries
        categories: [field_count]CategorySummary(CategoryType) = [_]CategorySummary(CategoryType){.{}} ** field_count,
        /// Overall budget status
        total_budget_allocated: f64 = 0,
        total_budget_used: f64 = 0,
        /// Deficit warnings
        deficit_warning: bool = false,
        reserve_warning: bool = false,

        /// Get summary for a specific category
        pub fn getCategory(self: *const Self, category: CategoryType) CategorySummary(CategoryType) {
            return self.categories[@intFromEnum(category)];
        }

        /// Check if profitable this turn
        pub fn isProfitable(self: *const Self) bool {
            return self.net_change > 0;
        }

        /// Get profit margin as percentage
        pub fn getProfitMargin(self: *const Self) f64 {
            if (self.total_income == 0) return 0;
            return (self.net_change / self.total_income) * 100;
        }

        /// Check if any category is over budget
        pub fn hasOverBudget(self: *const Self) bool {
            for (self.categories) |cat| {
                if (cat.over_budget) return true;
            }
            return false;
        }
    };
}

/// Loan record for debt tracking
pub const Loan = struct {
    /// Original principal amount
    principal: f64,
    /// Current outstanding balance
    balance: f64,
    /// Interest rate per turn
    interest_rate: f64,
    /// Turn when loan was taken
    turn_taken: u32,
    /// Optional: turn when loan must be repaid
    due_turn: ?u32 = null,
    /// Description/source of loan
    description: []const u8,
};

/// Finance manager for a category type
pub fn FinanceManager(comptime CategoryType: type) type {
    const category_info = @typeInfo(CategoryType);
    if (category_info != .@"enum") {
        @compileError("FinanceManager requires an enum type for categories, got " ++ @typeName(CategoryType));
    }

    const field_count = category_info.@"enum".fields.len;
    const TransactionT = Transaction(CategoryType);
    const ReportT = FinancialReport(CategoryType);

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        config: FinanceConfig,

        // Current state
        treasury: f64 = 0,
        debt: f64 = 0,
        current_turn: u32 = 0,

        // Per-category data
        budgets: [field_count]BudgetAllocation = [_]BudgetAllocation{.{}} ** field_count,
        category_income: [field_count]f64 = [_]f64{0} ** field_count,
        category_expenses: [field_count]f64 = [_]f64{0} ** field_count,
        category_transaction_counts: [field_count]u32 = [_]u32{0} ** field_count,

        // Transaction history (current turn)
        transactions: std.ArrayList(TransactionT),

        // Historical reports
        reports: std.ArrayList(ReportT),

        // Active loans
        loans: std.ArrayList(Loan),

        // Callbacks
        on_deficit: ?*const fn (amount: f64, context: ?*anyopaque) void = null,
        on_reserve_warning: ?*const fn (balance: f64, threshold: f64, context: ?*anyopaque) void = null,
        on_budget_exceeded: ?*const fn (category: CategoryType, amount: f64, budget: f64, context: ?*anyopaque) void = null,
        callback_context: ?*anyopaque = null,

        /// Initialize the finance manager
        pub fn init(allocator: std.mem.Allocator) Self {
            return initWithConfig(allocator, .{});
        }

        /// Initialize with custom configuration
        pub fn initWithConfig(allocator: std.mem.Allocator, config: FinanceConfig) Self {
            return Self{
                .allocator = allocator,
                .config = config,
                .transactions = .{},
                .reports = .{},
                .loans = .{},
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.transactions.deinit(self.allocator);
            self.reports.deinit(self.allocator);
            self.loans.deinit(self.allocator);
        }

        // ====== Treasury Management ======

        /// Get current treasury balance
        pub fn getTreasury(self: *const Self) f64 {
            return self.treasury;
        }

        /// Get current debt level
        pub fn getDebt(self: *const Self) f64 {
            return self.debt;
        }

        /// Get net worth (treasury - debt)
        pub fn getNetWorth(self: *const Self) f64 {
            return self.treasury - self.debt;
        }

        /// Set initial treasury balance
        pub fn setTreasury(self: *Self, amount: f64) void {
            self.treasury = amount;
        }

        /// Add to treasury directly (e.g., starting funds, cheats)
        pub fn addToTreasury(self: *Self, amount: f64) void {
            self.treasury += amount;
        }

        /// Check if treasury is in deficit
        pub fn isInDeficit(self: *const Self) bool {
            return self.treasury < 0;
        }

        /// Check if below reserve threshold
        pub fn isBelowReserve(self: *const Self) bool {
            return self.treasury < self.config.reserve_threshold;
        }

        // ====== Budget Management ======

        /// Set budget for a category
        pub fn setBudget(self: *Self, category: CategoryType, budget: BudgetAllocation) void {
            self.budgets[@intFromEnum(category)] = budget;
        }

        /// Get budget for a category
        pub fn getBudget(self: *const Self, category: CategoryType) BudgetAllocation {
            return self.budgets[@intFromEnum(category)];
        }

        /// Get remaining budget for a category
        pub fn getRemainingBudget(self: *const Self, category: CategoryType) f64 {
            const idx = @intFromEnum(category);
            const allocated = self.budgets[idx].allocated;
            const spent = self.category_expenses[idx];
            return @max(0, allocated - spent);
        }

        /// Get budget utilization percentage
        pub fn getBudgetUtilization(self: *const Self, category: CategoryType) f64 {
            const idx = @intFromEnum(category);
            const allocated = self.budgets[idx].allocated;
            if (allocated == 0) return 0;
            return (self.category_expenses[idx] / allocated) * 100;
        }

        /// Set total budget and distribute by percentage
        pub fn distributeBudget(self: *Self, total: f64, percentages: [field_count]f64) void {
            for (0..field_count) |i| {
                self.budgets[i].allocated = total * percentages[i];
            }
        }

        /// Get total allocated budget
        pub fn getTotalBudget(self: *const Self) f64 {
            var total: f64 = 0;
            for (self.budgets) |b| {
                total += b.allocated;
            }
            return total;
        }

        // ====== Transaction Recording ======

        /// Result of a transaction attempt
        pub const TransactionResult = enum {
            success,
            insufficient_funds,
            budget_exceeded,
            max_debt_exceeded,
            blocked_by_policy,
        };

        /// Record an income transaction
        pub fn recordIncome(self: *Self, category: CategoryType, amount: f64, description: []const u8) !void {
            const idx = @intFromEnum(category);

            self.treasury += amount;
            self.category_income[idx] += amount;
            self.category_transaction_counts[idx] += 1;

            if (self.config.detailed_logging) {
                try self.transactions.append(self.allocator, .{
                    .transaction_type = .income,
                    .category = category,
                    .amount = amount,
                    .turn = self.current_turn,
                    .description = description,
                });
            }
        }

        /// Record an expense transaction
        pub fn recordExpense(self: *Self, category: CategoryType, amount: f64, description: []const u8) !TransactionResult {
            const idx = @intFromEnum(category);
            const budget = self.budgets[idx];

            // Check budget limits
            const new_total = self.category_expenses[idx] + amount;
            var budget_approved = true;

            if (new_total > budget.allocated and budget.allocated > 0) {
                budget_approved = false;

                // Notify callback
                if (self.on_budget_exceeded) |callback| {
                    callback(category, new_total, budget.allocated, self.callback_context);
                }

                // Apply deficit policy
                switch (self.config.deficit_policy) {
                    .reject => return .budget_exceeded,
                    .allow_debt, .use_reserves, .proportional_cut, .priority_cut => {
                        // Continue with expense
                    },
                }
            }

            // Check maximum budget
            if (new_total > budget.maximum) {
                return .budget_exceeded;
            }

            // Check treasury policy
            if (self.treasury < amount) {
                switch (self.config.treasury_policy) {
                    .block_expenses => return .insufficient_funds,
                    .allow_negative => {
                        // Will create deficit
                        if (self.on_deficit) |callback| {
                            callback(amount - self.treasury, self.callback_context);
                        }
                    },
                    .warn_only => {
                        if (self.on_deficit) |callback| {
                            callback(amount - self.treasury, self.callback_context);
                        }
                    },
                    .emergency_loan => {
                        // Take automatic loan
                        const shortfall = amount - self.treasury;
                        try self.takeLoan(shortfall, self.config.debt_interest_rate, null, "Emergency loan");
                    },
                }
            }

            // Check max debt
            if (self.config.max_debt > 0) {
                const potential_debt = if (self.treasury < amount)
                    self.debt + (amount - self.treasury)
                else
                    self.debt;

                if (potential_debt > self.config.max_debt) {
                    return .max_debt_exceeded;
                }
            }

            // Record the expense
            self.treasury -= amount;
            self.category_expenses[idx] += amount;
            self.category_transaction_counts[idx] += 1;

            if (self.config.detailed_logging) {
                try self.transactions.append(self.allocator, .{
                    .transaction_type = .expense,
                    .category = category,
                    .amount = amount,
                    .turn = self.current_turn,
                    .description = description,
                    .budget_approved = budget_approved,
                });
            }

            // Check reserve warning
            if (self.isBelowReserve()) {
                if (self.on_reserve_warning) |callback| {
                    callback(self.treasury, self.config.reserve_threshold, self.callback_context);
                }
            }

            return .success;
        }

        /// Record a transfer between categories (no net treasury change)
        pub fn recordTransfer(self: *Self, from: CategoryType, to: CategoryType, amount: f64, description: []const u8) !TransactionResult {
            const from_idx = @intFromEnum(from);
            const to_idx = @intFromEnum(to);

            // Check if source has enough in this turn's income/budget
            const available = self.category_income[from_idx] - self.category_expenses[from_idx];
            if (available < amount) {
                return .insufficient_funds;
            }

            // Record as expense from source, income to destination
            self.category_expenses[from_idx] += amount;
            self.category_income[to_idx] += amount;

            if (self.config.detailed_logging) {
                try self.transactions.append(self.allocator, .{
                    .transaction_type = .transfer,
                    .category = from,
                    .amount = amount,
                    .turn = self.current_turn,
                    .description = description,
                });
            }

            return .success;
        }

        // ====== Loan Management ======

        /// Take out a loan
        pub fn takeLoan(self: *Self, amount: f64, interest_rate: f64, due_turn: ?u32, description: []const u8) !void {
            // Check max debt
            if (self.config.max_debt > 0 and self.debt + amount > self.config.max_debt) {
                return error.MaxDebtExceeded;
            }

            try self.loans.append(self.allocator, .{
                .principal = amount,
                .balance = amount,
                .interest_rate = interest_rate,
                .turn_taken = self.current_turn,
                .due_turn = due_turn,
                .description = description,
            });

            self.treasury += amount;
            self.debt += amount;

            if (self.config.detailed_logging) {
                // Record as a generic category (first enum value)
                const first_category: CategoryType = @enumFromInt(0);
                try self.transactions.append(self.allocator, .{
                    .transaction_type = .loan,
                    .category = first_category,
                    .amount = amount,
                    .turn = self.current_turn,
                    .description = description,
                });
            }
        }

        /// Repay a loan (or partial repayment)
        pub fn repayLoan(self: *Self, loan_index: usize, amount: f64) !TransactionResult {
            if (loan_index >= self.loans.items.len) {
                return .blocked_by_policy;
            }

            if (self.treasury < amount) {
                return .insufficient_funds;
            }

            var loan = &self.loans.items[loan_index];
            const repay_amount = @min(amount, loan.balance);

            self.treasury -= repay_amount;
            loan.balance -= repay_amount;
            self.debt -= repay_amount;

            // Remove loan if fully repaid
            if (loan.balance <= 0) {
                _ = self.loans.orderedRemove(loan_index);
            }

            return .success;
        }

        /// Get total loan count
        pub fn getLoanCount(self: *const Self) usize {
            return self.loans.items.len;
        }

        /// Get all active loans
        pub fn getLoans(self: *const Self) []const Loan {
            return self.loans.items;
        }

        // ====== Turn Processing ======

        /// Process interest on debt
        fn processInterest(self: *Self) !f64 {
            var total_interest: f64 = 0;

            for (self.loans.items) |*loan| {
                const interest = loan.balance * loan.interest_rate;
                loan.balance += interest;
                self.debt += interest;
                total_interest += interest;
            }

            return total_interest;
        }

        /// Process budget rollovers
        fn processRollovers(self: *Self) void {
            for (0..field_count) |i| {
                const budget = &self.budgets[i];
                if (budget.rollover and budget.rollover_percent > 0) {
                    const unused = @max(0, budget.allocated - self.category_expenses[i]);
                    const rollover_amount = unused * budget.rollover_percent;
                    budget.allocated = rollover_amount;
                }
            }
        }

        /// End the current turn and generate a report
        pub fn endTurn(self: *Self) !ReportT {
            // Calculate totals
            var total_income: f64 = 0;
            var total_expenses: f64 = 0;
            var total_budget_allocated: f64 = 0;
            var total_budget_used: f64 = 0;

            var report = ReportT{
                .turn = self.current_turn,
                .starting_balance = self.treasury,
            };

            // Build category summaries
            for (0..field_count) |i| {
                const income = self.category_income[i];
                const expenses = self.category_expenses[i];
                const budget = self.budgets[i];

                total_income += income;
                total_expenses += expenses;
                total_budget_allocated += budget.allocated;
                total_budget_used += @min(expenses, budget.allocated);

                report.categories[i] = .{
                    .income = income,
                    .expenses = expenses,
                    .net = income - expenses,
                    .budget_allocated = budget.allocated,
                    .budget_remaining = @max(0, budget.allocated - expenses),
                    .budget_utilization = if (budget.allocated > 0) (expenses / budget.allocated) * 100 else 0,
                    .transaction_count = self.category_transaction_counts[i],
                    .over_budget = expenses > budget.allocated and budget.allocated > 0,
                };
            }

            // Process interest
            const interest_paid = try self.processInterest();

            // Complete report
            report.total_income = total_income;
            report.total_expenses = total_expenses;
            report.net_change = total_income - total_expenses - interest_paid;
            report.ending_balance = self.treasury;
            report.debt = self.debt;
            report.interest_paid = interest_paid;
            report.total_budget_allocated = total_budget_allocated;
            report.total_budget_used = total_budget_used;
            report.deficit_warning = self.isInDeficit();
            report.reserve_warning = self.isBelowReserve();

            // Store report in history
            if (self.reports.items.len >= self.config.history_size) {
                _ = self.reports.orderedRemove(0);
            }
            try self.reports.append(self.allocator, report);

            // Process rollovers
            self.processRollovers();

            // Reset turn counters
            self.resetTurnCounters();

            // Advance turn
            self.current_turn += 1;

            return report;
        }

        /// Reset per-turn counters
        fn resetTurnCounters(self: *Self) void {
            @memset(&self.category_income, 0);
            @memset(&self.category_expenses, 0);
            @memset(&self.category_transaction_counts, 0);
            self.transactions.clearRetainingCapacity();
        }

        // ====== Queries ======

        /// Get current turn number
        pub fn getCurrentTurn(self: *const Self) u32 {
            return self.current_turn;
        }

        /// Get income for current turn by category
        pub fn getCategoryIncome(self: *const Self, category: CategoryType) f64 {
            return self.category_income[@intFromEnum(category)];
        }

        /// Get expenses for current turn by category
        pub fn getCategoryExpenses(self: *const Self, category: CategoryType) f64 {
            return self.category_expenses[@intFromEnum(category)];
        }

        /// Get net for current turn by category
        pub fn getCategoryNet(self: *const Self, category: CategoryType) f64 {
            const idx = @intFromEnum(category);
            return self.category_income[idx] - self.category_expenses[idx];
        }

        /// Get total income for current turn
        pub fn getTotalIncome(self: *const Self) f64 {
            var total: f64 = 0;
            for (self.category_income) |income| {
                total += income;
            }
            return total;
        }

        /// Get total expenses for current turn
        pub fn getTotalExpenses(self: *const Self) f64 {
            var total: f64 = 0;
            for (self.category_expenses) |expense| {
                total += expense;
            }
            return total;
        }

        /// Get projected balance at end of turn
        /// Since income/expenses are applied immediately to treasury, this returns the current treasury
        pub fn getProjectedBalance(self: *const Self) f64 {
            return self.treasury;
        }

        /// Get transactions for current turn
        pub fn getTransactions(self: *const Self) []const TransactionT {
            return self.transactions.items;
        }

        /// Get historical reports
        pub fn getReports(self: *const Self) []const ReportT {
            return self.reports.items;
        }

        /// Get the most recent report
        pub fn getLastReport(self: *const Self) ?ReportT {
            if (self.reports.items.len == 0) return null;
            return self.reports.items[self.reports.items.len - 1];
        }

        /// Get average income over N turns
        pub fn getAverageIncome(self: *const Self, turns: usize) f64 {
            if (self.reports.items.len == 0) return 0;
            const count = @min(turns, self.reports.items.len);
            var sum: f64 = 0;
            const start = self.reports.items.len - count;
            for (self.reports.items[start..]) |report| {
                sum += report.total_income;
            }
            return sum / @as(f64, @floatFromInt(count));
        }

        /// Get average expenses over N turns
        pub fn getAverageExpenses(self: *const Self, turns: usize) f64 {
            if (self.reports.items.len == 0) return 0;
            const count = @min(turns, self.reports.items.len);
            var sum: f64 = 0;
            const start = self.reports.items.len - count;
            for (self.reports.items[start..]) |report| {
                sum += report.total_expenses;
            }
            return sum / @as(f64, @floatFromInt(count));
        }

        /// Get turns until bankruptcy at current rate
        pub fn getTurnsToBankruptcy(self: *const Self) ?u32 {
            const net = self.getTotalIncome() - self.getTotalExpenses();
            if (net >= 0) return null; // Not losing money
            if (self.treasury <= 0) return 0; // Already bankrupt

            const turns = @as(u32, @intFromFloat(@ceil(self.treasury / (-net))));
            return turns;
        }

        // ====== Callbacks ======

        /// Set callback handlers
        pub fn setCallbacks(
            self: *Self,
            on_deficit: ?*const fn (f64, ?*anyopaque) void,
            on_reserve_warning: ?*const fn (f64, f64, ?*anyopaque) void,
            on_budget_exceeded: ?*const fn (CategoryType, f64, f64, ?*anyopaque) void,
            context: ?*anyopaque,
        ) void {
            self.on_deficit = on_deficit;
            self.on_reserve_warning = on_reserve_warning;
            self.on_budget_exceeded = on_budget_exceeded;
            self.callback_context = context;
        }

        // ====== Save/Load ======

        /// State structure for save/load
        pub const SaveState = struct {
            treasury: f64,
            debt: f64,
            current_turn: u32,
        };

        /// Get state for serialization
        pub fn getState(self: *const Self) SaveState {
            return .{
                .treasury = self.treasury,
                .debt = self.debt,
                .current_turn = self.current_turn,
            };
        }

        /// Restore state from serialization
        pub fn setState(self: *Self, state: SaveState) void {
            self.treasury = state.treasury;
            self.debt = state.debt;
            self.current_turn = state.current_turn;
        }

        /// Reset all financial data
        pub fn reset(self: *Self) void {
            self.treasury = 0;
            self.debt = 0;
            self.current_turn = 0;
            self.resetTurnCounters();
            self.transactions.clearRetainingCapacity();
            self.reports.clearRetainingCapacity();
            self.loans.clearRetainingCapacity();
            @memset(&self.budgets, .{});
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const TestCategory = enum {
    military,
    research,
    infrastructure,
    trade,
    diplomacy,
};

test "FinanceManager - init and deinit" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    try std.testing.expectEqual(@as(f64, 0), fm.getTreasury());
    try std.testing.expectEqual(@as(f64, 0), fm.getDebt());
    try std.testing.expectEqual(@as(u32, 0), fm.getCurrentTurn());
}

test "FinanceManager - treasury management" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(1000);
    try std.testing.expectEqual(@as(f64, 1000), fm.getTreasury());

    fm.addToTreasury(500);
    try std.testing.expectEqual(@as(f64, 1500), fm.getTreasury());

    try std.testing.expect(!fm.isInDeficit());
}

test "FinanceManager - record income" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    try fm.recordIncome(.trade, 1000, "Export revenue");
    try fm.recordIncome(.trade, 500, "Tax income");

    try std.testing.expectEqual(@as(f64, 1500), fm.getTreasury());
    try std.testing.expectEqual(@as(f64, 1500), fm.getCategoryIncome(.trade));
    try std.testing.expectEqual(@as(f64, 1500), fm.getTotalIncome());
}

test "FinanceManager - record expense" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(1000);

    const result = try fm.recordExpense(.military, 300, "Unit upkeep");
    try std.testing.expectEqual(FinanceManager(TestCategory).TransactionResult.success, result);

    try std.testing.expectEqual(@as(f64, 700), fm.getTreasury());
    try std.testing.expectEqual(@as(f64, 300), fm.getCategoryExpenses(.military));
}

test "FinanceManager - budget management" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(10000);
    fm.setBudget(.military, .{ .allocated = 2000, .priority = 1 });
    fm.setBudget(.research, .{ .allocated = 1500, .priority = 2 });

    try std.testing.expectEqual(@as(f64, 2000), fm.getBudget(.military).allocated);
    try std.testing.expectEqual(@as(f64, 3500), fm.getTotalBudget());
}

test "FinanceManager - budget remaining" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(10000);
    fm.setBudget(.military, .{ .allocated = 2000 });

    _ = try fm.recordExpense(.military, 500, "Expense 1");
    try std.testing.expectEqual(@as(f64, 1500), fm.getRemainingBudget(.military));

    _ = try fm.recordExpense(.military, 300, "Expense 2");
    try std.testing.expectEqual(@as(f64, 1200), fm.getRemainingBudget(.military));
}

test "FinanceManager - budget utilization" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(10000);
    fm.setBudget(.military, .{ .allocated = 1000 });

    _ = try fm.recordExpense(.military, 500, "Expense");
    try std.testing.expectApproxEqAbs(@as(f64, 50), fm.getBudgetUtilization(.military), 0.01);
}

test "FinanceManager - budget exceeded reject policy" {
    var fm = FinanceManager(TestCategory).initWithConfig(std.testing.allocator, .{
        .deficit_policy = .reject,
    });
    defer fm.deinit();

    fm.setTreasury(10000);
    fm.setBudget(.military, .{ .allocated = 500 });

    _ = try fm.recordExpense(.military, 400, "Within budget");
    const result = try fm.recordExpense(.military, 200, "Exceeds budget");

    try std.testing.expectEqual(FinanceManager(TestCategory).TransactionResult.budget_exceeded, result);
    try std.testing.expectEqual(@as(f64, 400), fm.getCategoryExpenses(.military));
}

test "FinanceManager - insufficient funds block policy" {
    var fm = FinanceManager(TestCategory).initWithConfig(std.testing.allocator, .{
        .treasury_policy = .block_expenses,
    });
    defer fm.deinit();

    fm.setTreasury(100);

    const result = try fm.recordExpense(.military, 500, "Too expensive");

    try std.testing.expectEqual(FinanceManager(TestCategory).TransactionResult.insufficient_funds, result);
    try std.testing.expectEqual(@as(f64, 100), fm.getTreasury()); // Unchanged
}

test "FinanceManager - end turn generates report" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(1000);

    try fm.recordIncome(.trade, 500, "Trade income");
    _ = try fm.recordExpense(.military, 200, "Upkeep");

    const report = try fm.endTurn();

    try std.testing.expectEqual(@as(u32, 0), report.turn);
    try std.testing.expectEqual(@as(f64, 500), report.total_income);
    try std.testing.expectEqual(@as(f64, 200), report.total_expenses);
    try std.testing.expectEqual(@as(f64, 300), report.net_change);
    try std.testing.expect(report.isProfitable());
}

test "FinanceManager - turn advances after end turn" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    try std.testing.expectEqual(@as(u32, 0), fm.getCurrentTurn());

    _ = try fm.endTurn();
    try std.testing.expectEqual(@as(u32, 1), fm.getCurrentTurn());

    _ = try fm.endTurn();
    try std.testing.expectEqual(@as(u32, 2), fm.getCurrentTurn());
}

test "FinanceManager - counters reset after end turn" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(1000);
    try fm.recordIncome(.trade, 500, "Income");
    _ = try fm.recordExpense(.military, 200, "Expense");

    try std.testing.expectEqual(@as(f64, 500), fm.getTotalIncome());
    try std.testing.expectEqual(@as(f64, 200), fm.getTotalExpenses());

    _ = try fm.endTurn();

    // Counters should be reset
    try std.testing.expectEqual(@as(f64, 0), fm.getTotalIncome());
    try std.testing.expectEqual(@as(f64, 0), fm.getTotalExpenses());
}

test "FinanceManager - loan taking" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    try std.testing.expectEqual(@as(f64, 0), fm.getTreasury());

    try fm.takeLoan(1000, 0.05, null, "Emergency funds");

    try std.testing.expectEqual(@as(f64, 1000), fm.getTreasury());
    try std.testing.expectEqual(@as(f64, 1000), fm.getDebt());
    try std.testing.expectEqual(@as(usize, 1), fm.getLoanCount());
}

test "FinanceManager - loan repayment" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(500);
    try fm.takeLoan(1000, 0.05, null, "Loan");

    try std.testing.expectEqual(@as(f64, 1500), fm.getTreasury());
    try std.testing.expectEqual(@as(f64, 1000), fm.getDebt());

    const result = try fm.repayLoan(0, 400);
    try std.testing.expectEqual(FinanceManager(TestCategory).TransactionResult.success, result);

    try std.testing.expectEqual(@as(f64, 1100), fm.getTreasury());
    try std.testing.expectEqual(@as(f64, 600), fm.getDebt());
}

test "FinanceManager - full loan repayment removes loan" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(2000);
    try fm.takeLoan(1000, 0.05, null, "Loan");

    try std.testing.expectEqual(@as(usize, 1), fm.getLoanCount());

    _ = try fm.repayLoan(0, 1000);

    try std.testing.expectEqual(@as(usize, 0), fm.getLoanCount());
    try std.testing.expectEqual(@as(f64, 0), fm.getDebt());
}

test "FinanceManager - interest accrual" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    try fm.takeLoan(1000, 0.10, null, "10% interest loan");

    const report = try fm.endTurn();

    // After one turn, 10% interest should accrue
    try std.testing.expectApproxEqAbs(@as(f64, 100), report.interest_paid, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 1100), fm.getDebt(), 0.01);
}

test "FinanceManager - report history" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(1000);

    for (0..5) |_| {
        try fm.recordIncome(.trade, 100, "Income");
        _ = try fm.endTurn();
    }

    try std.testing.expectEqual(@as(usize, 5), fm.getReports().len);

    const last = fm.getLastReport().?;
    try std.testing.expectEqual(@as(u32, 4), last.turn);
}

test "FinanceManager - average income calculation" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(10000);

    try fm.recordIncome(.trade, 100, "Turn 0");
    _ = try fm.endTurn();

    try fm.recordIncome(.trade, 200, "Turn 1");
    _ = try fm.endTurn();

    try fm.recordIncome(.trade, 300, "Turn 2");
    _ = try fm.endTurn();

    const avg = fm.getAverageIncome(3);
    try std.testing.expectApproxEqAbs(@as(f64, 200), avg, 0.01);
}

test "FinanceManager - turns to bankruptcy" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(1000);

    // No expenses = no bankruptcy
    try std.testing.expect(fm.getTurnsToBankruptcy() == null);

    // More income than expenses = no bankruptcy
    try fm.recordIncome(.trade, 500, "Income");
    _ = try fm.recordExpense(.military, 200, "Expense");
    try std.testing.expect(fm.getTurnsToBankruptcy() == null);
}

test "FinanceManager - net worth calculation" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(1000);
    try fm.takeLoan(300, 0.05, null, "Loan");

    try std.testing.expectEqual(@as(f64, 1300), fm.getTreasury());
    try std.testing.expectEqual(@as(f64, 300), fm.getDebt());
    try std.testing.expectEqual(@as(f64, 1000), fm.getNetWorth());
}

test "FinanceManager - category net calculation" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(10000);

    try fm.recordIncome(.trade, 1000, "Trade income");
    _ = try fm.recordExpense(.trade, 300, "Trade expense");

    try std.testing.expectEqual(@as(f64, 700), fm.getCategoryNet(.trade));
}

test "FinanceManager - projected balance" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(1000);

    try fm.recordIncome(.trade, 500, "Income");
    _ = try fm.recordExpense(.military, 200, "Expense");

    try std.testing.expectEqual(@as(f64, 1300), fm.getProjectedBalance());
}

test "FinanceManager - state save/restore" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(5000);
    try fm.takeLoan(1000, 0.05, null, "Loan");
    _ = try fm.endTurn();
    _ = try fm.endTurn();

    const state = fm.getState();
    try std.testing.expectEqual(@as(u32, 2), state.current_turn);

    // Create new manager and restore
    var fm2 = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm2.deinit();

    fm2.setState(state);
    try std.testing.expectEqual(fm.getTreasury(), fm2.getTreasury());
    try std.testing.expectEqual(fm.getCurrentTurn(), fm2.getCurrentTurn());
}

test "FinanceManager - reset" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(5000);
    try fm.recordIncome(.trade, 1000, "Income");
    _ = try fm.endTurn();
    _ = try fm.endTurn();

    fm.reset();

    try std.testing.expectEqual(@as(f64, 0), fm.getTreasury());
    try std.testing.expectEqual(@as(f64, 0), fm.getDebt());
    try std.testing.expectEqual(@as(u32, 0), fm.getCurrentTurn());
    try std.testing.expectEqual(@as(usize, 0), fm.getReports().len);
}

test "FinanceManager - profit margin calculation" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    fm.setTreasury(10000);

    try fm.recordIncome(.trade, 1000, "Income");
    _ = try fm.recordExpense(.military, 300, "Expense");

    const report = try fm.endTurn();

    // Net = 700, Income = 1000, Margin = 70%
    try std.testing.expectApproxEqAbs(@as(f64, 70), report.getProfitMargin(), 0.01);
}

test "FinanceManager - over budget detection" {
    var fm = FinanceManager(TestCategory).initWithConfig(std.testing.allocator, .{
        .deficit_policy = .allow_debt,
    });
    defer fm.deinit();

    fm.setTreasury(10000);
    fm.setBudget(.military, .{ .allocated = 500 });

    _ = try fm.recordExpense(.military, 800, "Over budget");

    const report = try fm.endTurn();

    try std.testing.expect(report.hasOverBudget());
    try std.testing.expect(report.getCategory(.military).over_budget);
}

test "FinanceManager - distribute budget" {
    var fm = FinanceManager(TestCategory).init(std.testing.allocator);
    defer fm.deinit();

    // Distribute 10000 total: 40% military, 30% research, 20% infrastructure, 10% trade, 0% diplomacy
    fm.distributeBudget(10000, .{ 0.4, 0.3, 0.2, 0.1, 0.0 });

    try std.testing.expectApproxEqAbs(@as(f64, 4000), fm.getBudget(.military).allocated, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 3000), fm.getBudget(.research).allocated, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 2000), fm.getBudget(.infrastructure).allocated, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 1000), fm.getBudget(.trade).allocated, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 0), fm.getBudget(.diplomacy).allocated, 0.01);
}

test "FinanceManager - max debt limit" {
    var fm = FinanceManager(TestCategory).initWithConfig(std.testing.allocator, .{
        .max_debt = 1000,
    });
    defer fm.deinit();

    try fm.takeLoan(500, 0.05, null, "First loan");
    try std.testing.expectEqual(@as(f64, 500), fm.getDebt());

    // Second loan should fail
    const result = fm.takeLoan(600, 0.05, null, "Second loan");
    try std.testing.expectError(error.MaxDebtExceeded, result);
}

test "FinanceManager - reserve warning threshold" {
    var fm = FinanceManager(TestCategory).initWithConfig(std.testing.allocator, .{
        .reserve_threshold = 500,
    });
    defer fm.deinit();

    fm.setTreasury(1000);

    try std.testing.expect(!fm.isBelowReserve());

    _ = try fm.recordExpense(.military, 600, "Expense");

    try std.testing.expect(fm.isBelowReserve());
}
