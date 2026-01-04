//! Trade System - Inter-Region Trade Routes and Market Simulation
//!
//! A comprehensive trade system for strategy games supporting trade routes,
//! supply/demand pricing, transport logistics, and trade agreements.
//!
//! Features:
//! - Trade route creation and management between regions
//! - Supply/demand-based dynamic pricing
//! - Transport costs based on distance and terrain
//! - Travel time simulation for goods in transit
//! - Trade agreements (tariffs, embargoes, most-favored-nation)
//! - Automatic trade route execution each turn
//! - Trade history and statistics
//!
//! Usage:
//! ```zig
//! const Resource = enum { food, ore, luxury, weapons };
//! const Region = enum { capital, port_city, mining_town, farmland };
//!
//! var trade = TradeSystem(Resource, Region).init(allocator);
//! defer trade.deinit();
//!
//! // Set up regional markets
//! try trade.setRegionProduction(.farmland, .food, 100);
//! try trade.setRegionDemand(.capital, .food, 150);
//!
//! // Create a trade route
//! const route_id = try trade.createRoute(.{
//!     .source = .farmland,
//!     .destination = .capital,
//!     .resource = .food,
//!     .amount_per_turn = 50,
//! });
//!
//! // Process a turn
//! const report = try trade.processTurn(current_turn);
//! ```

const std = @import("std");

const log = std.log.scoped(.trade);

/// Status of a trade route
pub const RouteStatus = enum {
    /// Route is active and executing trades
    active,
    /// Route is paused (manual or automatic)
    paused,
    /// Route is blocked (embargo, war, etc.)
    blocked,
    /// Route has insufficient supply at source
    insufficient_supply,
    /// Route has insufficient demand at destination
    insufficient_demand,
    /// Route has insufficient funds for transport
    insufficient_funds,
};

/// Type of trade agreement
pub const AgreementType = enum {
    /// Open trade with standard tariffs
    open_trade,
    /// Most favored nation - reduced tariffs
    most_favored_nation,
    /// Free trade - no tariffs
    free_trade,
    /// Trade embargo - no trade allowed
    embargo,
    /// Exclusive trade rights
    exclusive,
};

/// Configuration for trade system
pub const TradeConfig = struct {
    /// Base transport cost per unit distance
    base_transport_cost: f64 = 0.1,
    /// Base travel time per unit distance (in turns)
    base_travel_time: f64 = 0.1,
    /// Default tariff rate (as decimal, e.g., 0.1 = 10%)
    default_tariff_rate: f64 = 0.1,
    /// Price elasticity for demand (how much price changes with supply/demand imbalance)
    price_elasticity: f64 = 0.5,
    /// Minimum price multiplier (prevents prices from going to zero)
    min_price_multiplier: f64 = 0.25,
    /// Maximum price multiplier (prevents runaway prices)
    max_price_multiplier: f64 = 4.0,
    /// History size for completed trades
    history_size: usize = 100,
    /// Enable automatic price updates
    auto_update_prices: bool = true,
};

/// Market data for a resource in a region
pub const MarketData = struct {
    /// Base price of the resource
    base_price: f64 = 100,
    /// Current market price (affected by supply/demand)
    current_price: f64 = 100,
    /// Amount produced per turn in this region
    production: f64 = 0,
    /// Amount consumed/demanded per turn in this region
    demand: f64 = 0,
    /// Current stockpile in region
    stockpile: f64 = 0,
    /// Maximum storage capacity (0 = unlimited)
    storage_capacity: f64 = 0,
    /// Whether this region produces this resource
    is_producer: bool = false,
    /// Whether this region consumes this resource
    is_consumer: bool = false,
};

/// Trade route definition
pub fn TradeRoute(comptime ResourceType: type, comptime RegionType: type) type {
    return struct {
        const Self = @This();

        /// Unique identifier for this route
        id: u32,
        /// Source region
        source: RegionType,
        /// Destination region
        destination: RegionType,
        /// Resource being traded
        resource: ResourceType,
        /// Amount to trade per turn (attempted)
        amount_per_turn: f64,
        /// Current status of the route
        status: RouteStatus = .active,
        /// Distance between regions (for cost/time calculation)
        distance: f64 = 1.0,
        /// Terrain modifier for transport costs (1.0 = normal)
        terrain_modifier: f64 = 1.0,
        /// Turn when route was created
        created_turn: u32 = 0,
        /// Total amount traded over lifetime
        total_traded: f64 = 0,
        /// Total revenue generated
        total_revenue: f64 = 0,
        /// Total transport costs paid
        total_transport_costs: f64 = 0,
        /// Whether route automatically adjusts to supply/demand
        auto_adjust: bool = false,
        /// Minimum profit margin required (for auto-pause)
        min_profit_margin: f64 = 0,
        /// Custom name for the route
        name: ?[]const u8 = null,
        /// Priority for execution order (higher = first)
        priority: u8 = 100,

        /// Calculate transport cost for an amount
        pub fn getTransportCost(self: *const Self, amount: f64, config: TradeConfig) f64 {
            return amount * config.base_transport_cost * self.distance * self.terrain_modifier;
        }

        /// Calculate travel time in turns
        pub fn getTravelTime(self: *const Self, config: TradeConfig) u32 {
            const time = config.base_travel_time * self.distance * self.terrain_modifier;
            return @max(1, @as(u32, @intFromFloat(@ceil(time))));
        }

        /// Get profit for a trade (revenue - costs)
        pub fn getProfit(self: *const Self) f64 {
            return self.total_revenue - self.total_transport_costs;
        }

        /// Get average profit per unit traded
        pub fn getAverageProfitPerUnit(self: *const Self) f64 {
            if (self.total_traded == 0) return 0;
            return self.getProfit() / self.total_traded;
        }
    };
}

/// Goods currently in transit
pub fn GoodsInTransit(comptime ResourceType: type, comptime RegionType: type) type {
    return struct {
        /// Route this shipment belongs to
        route_id: u32,
        /// Resource being transported
        resource: ResourceType,
        /// Amount being transported
        amount: f64,
        /// Source region
        source: RegionType,
        /// Destination region
        destination: RegionType,
        /// Turn when shipment departed
        departure_turn: u32,
        /// Turn when shipment arrives
        arrival_turn: u32,
        /// Price locked in at departure
        locked_price: f64,
    };
}

/// Trade agreement between regions/players
pub fn TradeAgreement(comptime RegionType: type) type {
    return struct {
        /// First party (region or player ID)
        party_a: RegionType,
        /// Second party
        party_b: RegionType,
        /// Type of agreement
        agreement_type: AgreementType,
        /// Tariff rate for party A's exports to B (0 = no tariff)
        tariff_a_to_b: f64 = 0,
        /// Tariff rate for party B's exports to A
        tariff_b_to_a: f64 = 0,
        /// Turn when agreement was established
        established_turn: u32 = 0,
        /// Turn when agreement expires (null = permanent)
        expires_turn: ?u32 = null,
        /// Whether agreement is currently active
        active: bool = true,
    };
}

/// Record of a completed trade
pub fn TradeRecord(comptime ResourceType: type, comptime RegionType: type) type {
    return struct {
        /// Route ID
        route_id: u32,
        /// Resource traded
        resource: ResourceType,
        /// Source region
        source: RegionType,
        /// Destination region
        destination: RegionType,
        /// Amount traded
        amount: f64,
        /// Price per unit
        price: f64,
        /// Total revenue
        revenue: f64,
        /// Transport cost
        transport_cost: f64,
        /// Tariff paid
        tariff: f64,
        /// Net profit
        profit: f64,
        /// Turn when trade occurred
        turn: u32,
    };
}

/// Per-turn trade report
pub fn TradeReport(comptime ResourceType: type, comptime RegionType: type) type {
    _ = RegionType;
    _ = ResourceType;
    return struct {
        /// Turn number
        turn: u32,
        /// Total trades executed
        trades_executed: u32 = 0,
        /// Total amount traded across all resources
        total_amount: f64 = 0,
        /// Total revenue generated
        total_revenue: f64 = 0,
        /// Total transport costs
        total_transport_costs: f64 = 0,
        /// Total tariffs paid
        total_tariffs: f64 = 0,
        /// Total profit (revenue - costs - tariffs)
        total_profit: f64 = 0,
        /// Number of routes blocked
        routes_blocked: u32 = 0,
        /// Number of routes with insufficient supply
        routes_insufficient_supply: u32 = 0,
        /// Number of shipments arriving this turn
        shipments_arrived: u32 = 0,
        /// Number of new shipments departing
        shipments_departed: u32 = 0,
    };
}

/// Main trade system manager
pub fn TradeSystem(comptime ResourceType: type, comptime RegionType: type) type {
    const resource_info = @typeInfo(ResourceType);
    const region_info = @typeInfo(RegionType);

    if (resource_info != .@"enum") {
        @compileError("TradeSystem requires an enum type for resources, got " ++ @typeName(ResourceType));
    }
    if (region_info != .@"enum") {
        @compileError("TradeSystem requires an enum type for regions, got " ++ @typeName(RegionType));
    }

    const resource_count = resource_info.@"enum".fields.len;
    const region_count = region_info.@"enum".fields.len;

    const RouteT = TradeRoute(ResourceType, RegionType);
    const TransitT = GoodsInTransit(ResourceType, RegionType);
    const AgreementT = TradeAgreement(RegionType);
    const RecordT = TradeRecord(ResourceType, RegionType);
    const ReportT = TradeReport(ResourceType, RegionType);

    return struct {
        const Self = @This();

        /// Market key for region + resource combination
        const MarketKey = struct {
            region: RegionType,
            resource: ResourceType,
        };

        allocator: std.mem.Allocator,
        config: TradeConfig,

        /// Next route ID
        next_route_id: u32 = 1,

        /// Current turn
        current_turn: u32 = 0,

        /// All trade routes
        routes: std.ArrayList(RouteT),

        /// Goods currently in transit
        in_transit: std.ArrayList(TransitT),

        /// Trade agreements
        agreements: std.ArrayList(AgreementT),

        /// Trade history
        history: std.ArrayList(RecordT),

        /// Historical reports
        reports: std.ArrayList(ReportT),

        /// Market data per region per resource
        /// Using a flat array: markets[region_idx * resource_count + resource_idx]
        markets: [region_count * resource_count]MarketData,

        /// Callbacks
        on_trade_completed: ?*const fn (record: RecordT, context: ?*anyopaque) void = null,
        on_route_status_changed: ?*const fn (route_id: u32, old_status: RouteStatus, new_status: RouteStatus, context: ?*anyopaque) void = null,
        on_price_changed: ?*const fn (region: RegionType, resource: ResourceType, old_price: f64, new_price: f64, context: ?*anyopaque) void = null,
        on_shipment_arrived: ?*const fn (transit: TransitT, context: ?*anyopaque) void = null,
        callback_context: ?*anyopaque = null,

        /// Initialize the trade system
        pub fn init(allocator: std.mem.Allocator) Self {
            return initWithConfig(allocator, .{});
        }

        /// Initialize with custom configuration
        pub fn initWithConfig(allocator: std.mem.Allocator, config: TradeConfig) Self {
            return Self{
                .allocator = allocator,
                .config = config,
                .routes = .{},
                .in_transit = .{},
                .agreements = .{},
                .history = .{},
                .reports = .{},
                .markets = [_]MarketData{.{}} ** (region_count * resource_count),
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.routes.deinit(self.allocator);
            self.in_transit.deinit(self.allocator);
            self.agreements.deinit(self.allocator);
            self.history.deinit(self.allocator);
            self.reports.deinit(self.allocator);
        }

        // ====== Market Index Helper ======

        fn getMarketIndex(region: RegionType, resource: ResourceType) usize {
            return @intFromEnum(region) * resource_count + @intFromEnum(resource);
        }

        // ====== Market Management ======

        /// Get market data for a region/resource
        pub fn getMarket(self: *const Self, region: RegionType, resource: ResourceType) MarketData {
            return self.markets[getMarketIndex(region, resource)];
        }

        /// Get mutable market data
        fn getMarketPtr(self: *Self, region: RegionType, resource: ResourceType) *MarketData {
            return &self.markets[getMarketIndex(region, resource)];
        }

        /// Set base price for a resource in a region
        pub fn setBasePrice(self: *Self, region: RegionType, resource: ResourceType, price: f64) void {
            const market = self.getMarketPtr(region, resource);
            market.base_price = price;
            market.current_price = price;
        }

        /// Set production rate for a region
        pub fn setRegionProduction(self: *Self, region: RegionType, resource: ResourceType, amount: f64) void {
            const market = self.getMarketPtr(region, resource);
            market.production = amount;
            market.is_producer = amount > 0;
        }

        /// Set demand/consumption for a region
        pub fn setRegionDemand(self: *Self, region: RegionType, resource: ResourceType, amount: f64) void {
            const market = self.getMarketPtr(region, resource);
            market.demand = amount;
            market.is_consumer = amount > 0;
        }

        /// Set stockpile amount
        pub fn setStockpile(self: *Self, region: RegionType, resource: ResourceType, amount: f64) void {
            const market = self.getMarketPtr(region, resource);
            market.stockpile = amount;
        }

        /// Add to stockpile
        pub fn addToStockpile(self: *Self, region: RegionType, resource: ResourceType, amount: f64) void {
            const market = self.getMarketPtr(region, resource);
            market.stockpile += amount;
            if (market.storage_capacity > 0) {
                market.stockpile = @min(market.stockpile, market.storage_capacity);
            }
        }

        /// Remove from stockpile (returns actual amount removed)
        pub fn removeFromStockpile(self: *Self, region: RegionType, resource: ResourceType, amount: f64) f64 {
            const market = self.getMarketPtr(region, resource);
            const removed = @min(amount, market.stockpile);
            market.stockpile -= removed;
            return removed;
        }

        /// Set storage capacity
        pub fn setStorageCapacity(self: *Self, region: RegionType, resource: ResourceType, capacity: f64) void {
            const market = self.getMarketPtr(region, resource);
            market.storage_capacity = capacity;
            if (capacity > 0 and market.stockpile > capacity) {
                market.stockpile = capacity;
            }
        }

        /// Get current price for a resource in a region
        pub fn getPrice(self: *const Self, region: RegionType, resource: ResourceType) f64 {
            return self.markets[getMarketIndex(region, resource)].current_price;
        }

        /// Get supply/demand ratio (> 1 means surplus, < 1 means shortage)
        pub fn getSupplyDemandRatio(self: *const Self, region: RegionType, resource: ResourceType) f64 {
            const market = self.markets[getMarketIndex(region, resource)];
            if (market.demand == 0) {
                return if (market.production > 0 or market.stockpile > 0) 999.0 else 1.0;
            }
            return (market.production + market.stockpile) / market.demand;
        }

        /// Update prices based on supply/demand
        pub fn updatePrices(self: *Self) void {
            for (0..region_count) |region_idx| {
                for (0..resource_count) |resource_idx| {
                    const idx = region_idx * resource_count + resource_idx;
                    const market = &self.markets[idx];

                    if (market.base_price == 0) continue;

                    const old_price = market.current_price;

                    // Calculate supply/demand ratio
                    var ratio: f64 = 1.0;
                    if (market.demand > 0) {
                        ratio = (market.production + market.stockpile) / market.demand;
                    } else if (market.production > 0 or market.stockpile > 0) {
                        ratio = 2.0; // Surplus with no demand
                    }

                    // Calculate price multiplier based on ratio
                    // ratio < 1 (shortage) -> price goes up
                    // ratio > 1 (surplus) -> price goes down
                    var multiplier: f64 = 1.0;
                    if (ratio < 1.0) {
                        // Shortage - price increases
                        multiplier = 1.0 + (1.0 - ratio) * self.config.price_elasticity;
                    } else if (ratio > 1.0) {
                        // Surplus - price decreases
                        multiplier = 1.0 - (ratio - 1.0) * self.config.price_elasticity * 0.5;
                    }

                    // Clamp multiplier
                    multiplier = @max(self.config.min_price_multiplier, @min(self.config.max_price_multiplier, multiplier));

                    market.current_price = market.base_price * multiplier;

                    // Trigger callback if price changed significantly
                    if (@abs(market.current_price - old_price) > 0.01) {
                        if (self.on_price_changed) |callback| {
                            callback(
                                @enumFromInt(region_idx),
                                @enumFromInt(resource_idx),
                                old_price,
                                market.current_price,
                                self.callback_context,
                            );
                        }
                    }
                }
            }
        }

        // ====== Route Management ======

        /// Route creation options
        pub const RouteOptions = struct {
            source: RegionType,
            destination: RegionType,
            resource: ResourceType,
            amount_per_turn: f64,
            distance: f64 = 1.0,
            terrain_modifier: f64 = 1.0,
            auto_adjust: bool = false,
            min_profit_margin: f64 = 0,
            name: ?[]const u8 = null,
            priority: u8 = 100,
        };

        /// Create a new trade route
        pub fn createRoute(self: *Self, options: RouteOptions) !u32 {
            const route_id = self.next_route_id;
            self.next_route_id += 1;

            try self.routes.append(self.allocator, .{
                .id = route_id,
                .source = options.source,
                .destination = options.destination,
                .resource = options.resource,
                .amount_per_turn = options.amount_per_turn,
                .distance = options.distance,
                .terrain_modifier = options.terrain_modifier,
                .auto_adjust = options.auto_adjust,
                .min_profit_margin = options.min_profit_margin,
                .name = options.name,
                .priority = options.priority,
                .created_turn = self.current_turn,
            });

            return route_id;
        }

        /// Get a route by ID
        pub fn getRoute(self: *const Self, route_id: u32) ?RouteT {
            for (self.routes.items) |route| {
                if (route.id == route_id) return route;
            }
            return null;
        }

        /// Get mutable route by ID
        fn getRoutePtr(self: *Self, route_id: u32) ?*RouteT {
            for (self.routes.items) |*route| {
                if (route.id == route_id) return route;
            }
            return null;
        }

        /// Delete a trade route
        pub fn deleteRoute(self: *Self, route_id: u32) bool {
            for (self.routes.items, 0..) |route, i| {
                if (route.id == route_id) {
                    _ = self.routes.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        /// Set route status
        pub fn setRouteStatus(self: *Self, route_id: u32, status: RouteStatus) void {
            if (self.getRoutePtr(route_id)) |route| {
                const old_status = route.status;
                route.status = status;

                if (self.on_route_status_changed) |callback| {
                    callback(route_id, old_status, status, self.callback_context);
                }
            }
        }

        /// Pause a route
        pub fn pauseRoute(self: *Self, route_id: u32) void {
            self.setRouteStatus(route_id, .paused);
        }

        /// Resume a paused route
        pub fn resumeRoute(self: *Self, route_id: u32) void {
            self.setRouteStatus(route_id, .active);
        }

        /// Get all routes
        pub fn getRoutes(self: *const Self) []const RouteT {
            return self.routes.items;
        }

        /// Get routes for a specific source region
        pub fn getRoutesFromRegion(self: *const Self, allocator: std.mem.Allocator, region: RegionType) ![]const RouteT {
            var result: std.ArrayList(RouteT) = .{};
            for (self.routes.items) |route| {
                if (route.source == region) {
                    try result.append(allocator, route);
                }
            }
            return result.toOwnedSlice(allocator);
        }

        /// Get routes to a specific destination region
        pub fn getRoutesToRegion(self: *const Self, allocator: std.mem.Allocator, region: RegionType) ![]const RouteT {
            var result: std.ArrayList(RouteT) = .{};
            for (self.routes.items) |route| {
                if (route.destination == region) {
                    try result.append(allocator, route);
                }
            }
            return result.toOwnedSlice(allocator);
        }

        /// Get route count
        pub fn getRouteCount(self: *const Self) usize {
            return self.routes.items.len;
        }

        /// Get route count by status
        pub fn getRouteCountByStatus(self: *const Self, status: RouteStatus) usize {
            var count: usize = 0;
            for (self.routes.items) |route| {
                if (route.status == status) count += 1;
            }
            return count;
        }

        // ====== Agreement Management ======

        /// Create a trade agreement
        pub fn createAgreement(
            self: *Self,
            party_a: RegionType,
            party_b: RegionType,
            agreement_type: AgreementType,
            tariff_a_to_b: f64,
            tariff_b_to_a: f64,
            expires_turn: ?u32,
        ) !void {
            // Remove any existing agreement between these parties
            self.removeAgreement(party_a, party_b);

            try self.agreements.append(self.allocator, .{
                .party_a = party_a,
                .party_b = party_b,
                .agreement_type = agreement_type,
                .tariff_a_to_b = tariff_a_to_b,
                .tariff_b_to_a = tariff_b_to_a,
                .established_turn = self.current_turn,
                .expires_turn = expires_turn,
            });

            // If embargo, block affected routes
            if (agreement_type == .embargo) {
                for (self.routes.items) |*route| {
                    if ((route.source == party_a and route.destination == party_b) or
                        (route.source == party_b and route.destination == party_a))
                    {
                        self.setRouteStatus(route.id, .blocked);
                    }
                }
            }
        }

        /// Remove a trade agreement
        pub fn removeAgreement(self: *Self, party_a: RegionType, party_b: RegionType) void {
            var i: usize = 0;
            while (i < self.agreements.items.len) {
                const agreement = self.agreements.items[i];
                if ((agreement.party_a == party_a and agreement.party_b == party_b) or
                    (agreement.party_a == party_b and agreement.party_b == party_a))
                {
                    _ = self.agreements.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        /// Get agreement between two parties
        pub fn getAgreement(self: *const Self, party_a: RegionType, party_b: RegionType) ?AgreementT {
            for (self.agreements.items) |agreement| {
                if ((agreement.party_a == party_a and agreement.party_b == party_b) or
                    (agreement.party_a == party_b and agreement.party_b == party_a))
                {
                    return agreement;
                }
            }
            return null;
        }

        /// Get tariff rate for a trade
        pub fn getTariffRate(self: *const Self, source: RegionType, destination: RegionType) f64 {
            if (self.getAgreement(source, destination)) |agreement| {
                // Determine direction
                if (agreement.party_a == source) {
                    return agreement.tariff_a_to_b;
                } else {
                    return agreement.tariff_b_to_a;
                }
            }
            return self.config.default_tariff_rate;
        }

        /// Check if trade is allowed between regions
        pub fn isTradeAllowed(self: *const Self, source: RegionType, destination: RegionType) bool {
            if (self.getAgreement(source, destination)) |agreement| {
                if (!agreement.active) return true; // Inactive agreement doesn't block
                return agreement.agreement_type != .embargo;
            }
            return true; // No agreement = allowed
        }

        // ====== Trade Execution ======

        /// Execute a single trade for a route
        fn executeTrade(self: *Self, route: *RouteT, report: *ReportT) !void {
            // Check if trade is allowed
            if (!self.isTradeAllowed(route.source, route.destination)) {
                if (route.status != .blocked) {
                    self.setRouteStatus(route.id, .blocked);
                }
                report.routes_blocked += 1;
                return;
            }

            const source_market = self.getMarketPtr(route.source, route.resource);
            const dest_market = self.getMarket(route.destination, route.resource);

            // Check supply at source
            const available = source_market.stockpile;
            if (available < route.amount_per_turn * 0.1) { // Allow some flexibility
                if (route.status != .insufficient_supply) {
                    self.setRouteStatus(route.id, .insufficient_supply);
                }
                report.routes_insufficient_supply += 1;
                return;
            }

            // Determine actual trade amount
            var trade_amount = @min(route.amount_per_turn, available);

            // Auto-adjust based on destination demand
            if (route.auto_adjust) {
                const dest_need = dest_market.demand - dest_market.stockpile;
                if (dest_need <= 0) {
                    trade_amount = 0;
                } else {
                    trade_amount = @min(trade_amount, dest_need);
                }
            }

            if (trade_amount <= 0) return;

            // Calculate costs
            const transport_cost = route.getTransportCost(trade_amount, self.config);
            const price = dest_market.current_price;
            const revenue = trade_amount * price;
            const tariff_rate = self.getTariffRate(route.source, route.destination);
            const tariff = revenue * tariff_rate;
            const profit = revenue - transport_cost - tariff;

            // Check minimum profit margin
            if (route.min_profit_margin > 0) {
                const margin = if (revenue > 0) profit / revenue else 0;
                if (margin < route.min_profit_margin) {
                    if (route.status == .active) {
                        self.setRouteStatus(route.id, .paused);
                    }
                    return;
                }
            }

            // Execute the trade
            source_market.stockpile -= trade_amount;

            // Create shipment in transit
            const travel_time = route.getTravelTime(self.config);
            try self.in_transit.append(self.allocator, .{
                .route_id = route.id,
                .resource = route.resource,
                .amount = trade_amount,
                .source = route.source,
                .destination = route.destination,
                .departure_turn = self.current_turn,
                .arrival_turn = self.current_turn + travel_time,
                .locked_price = price,
            });

            // Update route stats
            route.total_traded += trade_amount;
            route.total_revenue += revenue;
            route.total_transport_costs += transport_cost;

            // Ensure route is marked active
            if (route.status != .active) {
                self.setRouteStatus(route.id, .active);
            }

            // Update report
            report.trades_executed += 1;
            report.total_amount += trade_amount;
            report.total_revenue += revenue;
            report.total_transport_costs += transport_cost;
            report.total_tariffs += tariff;
            report.total_profit += profit;
            report.shipments_departed += 1;

            // Record trade
            const record = RecordT{
                .route_id = route.id,
                .resource = route.resource,
                .source = route.source,
                .destination = route.destination,
                .amount = trade_amount,
                .price = price,
                .revenue = revenue,
                .transport_cost = transport_cost,
                .tariff = tariff,
                .profit = profit,
                .turn = self.current_turn,
            };

            // Add to history
            if (self.history.items.len >= self.config.history_size) {
                _ = self.history.orderedRemove(0);
            }
            try self.history.append(self.allocator, record);

            // Trigger callback
            if (self.on_trade_completed) |callback| {
                callback(record, self.callback_context);
            }
        }

        /// Process arriving shipments
        fn processArrivals(self: *Self, report: *ReportT) void {
            var i: usize = 0;
            while (i < self.in_transit.items.len) {
                const shipment = self.in_transit.items[i];
                if (shipment.arrival_turn <= self.current_turn) {
                    // Deliver goods
                    self.addToStockpile(shipment.destination, shipment.resource, shipment.amount);
                    report.shipments_arrived += 1;

                    // Trigger callback
                    if (self.on_shipment_arrived) |callback| {
                        callback(shipment, self.callback_context);
                    }

                    _ = self.in_transit.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        /// Process expired agreements
        fn processAgreements(self: *Self) void {
            var i: usize = 0;
            while (i < self.agreements.items.len) {
                const agreement = &self.agreements.items[i];
                if (agreement.expires_turn) |expires| {
                    if (expires <= self.current_turn) {
                        // Unblock routes that were blocked by this embargo
                        if (agreement.agreement_type == .embargo) {
                            for (self.routes.items) |*route| {
                                if (route.status == .blocked) {
                                    if ((route.source == agreement.party_a and route.destination == agreement.party_b) or
                                        (route.source == agreement.party_b and route.destination == agreement.party_a))
                                    {
                                        route.status = .active;
                                    }
                                }
                            }
                        }
                        _ = self.agreements.orderedRemove(i);
                        continue;
                    }
                }
                i += 1;
            }
        }

        /// Apply production to stockpiles
        fn applyProduction(self: *Self) void {
            for (0..region_count) |region_idx| {
                for (0..resource_count) |resource_idx| {
                    const market = &self.markets[region_idx * resource_count + resource_idx];
                    if (market.production > 0) {
                        market.stockpile += market.production;
                        if (market.storage_capacity > 0) {
                            market.stockpile = @min(market.stockpile, market.storage_capacity);
                        }
                    }
                }
            }
        }

        /// Apply consumption from stockpiles
        fn applyConsumption(self: *Self) void {
            for (0..region_count) |region_idx| {
                for (0..resource_count) |resource_idx| {
                    const market = &self.markets[region_idx * resource_count + resource_idx];
                    if (market.demand > 0) {
                        market.stockpile = @max(0, market.stockpile - market.demand);
                    }
                }
            }
        }

        /// Process a complete turn
        pub fn processTurn(self: *Self) !ReportT {
            var report = ReportT{ .turn = self.current_turn };

            // Apply production first
            self.applyProduction();

            // Process arriving shipments
            self.processArrivals(&report);

            // Update prices before trading
            if (self.config.auto_update_prices) {
                self.updatePrices();
            }

            // Sort routes by priority (higher first)
            std.mem.sort(RouteT, self.routes.items, {}, struct {
                fn lessThan(_: void, a: RouteT, b: RouteT) bool {
                    return a.priority > b.priority;
                }
            }.lessThan);

            // Execute trades for active routes
            for (self.routes.items) |*route| {
                if (route.status == .active or route.status == .insufficient_supply) {
                    try self.executeTrade(route, &report);
                }
            }

            // Apply consumption after trading
            self.applyConsumption();

            // Store report
            if (self.reports.items.len >= self.config.history_size) {
                _ = self.reports.orderedRemove(0);
            }
            try self.reports.append(self.allocator, report);

            // Advance turn
            self.current_turn += 1;

            // Process expired agreements (after turn advances)
            self.processAgreements();

            return report;
        }

        // ====== Queries ======

        /// Get current turn
        pub fn getCurrentTurn(self: *const Self) u32 {
            return self.current_turn;
        }

        /// Get goods in transit
        pub fn getInTransit(self: *const Self) []const TransitT {
            return self.in_transit.items;
        }

        /// Get count of goods in transit
        pub fn getInTransitCount(self: *const Self) usize {
            return self.in_transit.items.len;
        }

        /// Get trade history
        pub fn getHistory(self: *const Self) []const RecordT {
            return self.history.items;
        }

        /// Get historical reports
        pub fn getReports(self: *const Self) []const ReportT {
            return self.reports.items;
        }

        /// Get most recent report
        pub fn getLastReport(self: *const Self) ?ReportT {
            if (self.reports.items.len == 0) return null;
            return self.reports.items[self.reports.items.len - 1];
        }

        /// Get total trade volume for a resource
        pub fn getTotalTradeVolume(self: *const Self, resource: ResourceType) f64 {
            var total: f64 = 0;
            for (self.history.items) |record| {
                if (record.resource == resource) {
                    total += record.amount;
                }
            }
            return total;
        }

        /// Get total trade revenue
        pub fn getTotalRevenue(self: *const Self) f64 {
            var total: f64 = 0;
            for (self.history.items) |record| {
                total += record.revenue;
            }
            return total;
        }

        /// Get total trade profit
        pub fn getTotalProfit(self: *const Self) f64 {
            var total: f64 = 0;
            for (self.history.items) |record| {
                total += record.profit;
            }
            return total;
        }

        /// Get average price for a resource across all regions
        pub fn getAveragePrice(self: *const Self, resource: ResourceType) f64 {
            var total: f64 = 0;
            var count: f64 = 0;
            for (0..region_count) |region_idx| {
                const market = self.markets[region_idx * resource_count + @intFromEnum(resource)];
                if (market.current_price > 0) {
                    total += market.current_price;
                    count += 1;
                }
            }
            if (count == 0) return 0;
            return total / count;
        }

        /// Get agreements
        pub fn getAgreements(self: *const Self) []const AgreementT {
            return self.agreements.items;
        }

        // ====== Callbacks ======

        /// Set callback handlers
        pub fn setCallbacks(
            self: *Self,
            on_trade_completed: ?*const fn (RecordT, ?*anyopaque) void,
            on_route_status_changed: ?*const fn (u32, RouteStatus, RouteStatus, ?*anyopaque) void,
            on_price_changed: ?*const fn (RegionType, ResourceType, f64, f64, ?*anyopaque) void,
            on_shipment_arrived: ?*const fn (TransitT, ?*anyopaque) void,
            context: ?*anyopaque,
        ) void {
            self.on_trade_completed = on_trade_completed;
            self.on_route_status_changed = on_route_status_changed;
            self.on_price_changed = on_price_changed;
            self.on_shipment_arrived = on_shipment_arrived;
            self.callback_context = context;
        }

        /// Reset the trade system
        pub fn reset(self: *Self) void {
            self.routes.clearRetainingCapacity();
            self.in_transit.clearRetainingCapacity();
            self.agreements.clearRetainingCapacity();
            self.history.clearRetainingCapacity();
            self.reports.clearRetainingCapacity();
            @memset(&self.markets, .{});
            self.next_route_id = 1;
            self.current_turn = 0;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const TestResource = enum { food, ore, luxury, weapons };
const TestRegion = enum { capital, port_city, mining_town, farmland };

test "TradeSystem - init and deinit" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    try std.testing.expectEqual(@as(u32, 0), trade.getCurrentTurn());
    try std.testing.expectEqual(@as(usize, 0), trade.getRouteCount());
}

test "TradeSystem - market setup" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.farmland, .food, 50);
    trade.setRegionProduction(.farmland, .food, 100);
    trade.setRegionDemand(.capital, .food, 150);
    trade.setStockpile(.farmland, .food, 200);

    const farmland_market = trade.getMarket(.farmland, .food);
    try std.testing.expectEqual(@as(f64, 50), farmland_market.base_price);
    try std.testing.expectEqual(@as(f64, 100), farmland_market.production);
    try std.testing.expectEqual(@as(f64, 200), farmland_market.stockpile);
    try std.testing.expect(farmland_market.is_producer);

    const capital_market = trade.getMarket(.capital, .food);
    try std.testing.expectEqual(@as(f64, 150), capital_market.demand);
    try std.testing.expect(capital_market.is_consumer);
}

test "TradeSystem - create route" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    const route_id = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    try std.testing.expectEqual(@as(u32, 1), route_id);
    try std.testing.expectEqual(@as(usize, 1), trade.getRouteCount());

    const route = trade.getRoute(route_id).?;
    try std.testing.expectEqual(TestRegion.farmland, route.source);
    try std.testing.expectEqual(TestRegion.capital, route.destination);
    try std.testing.expectEqual(TestResource.food, route.resource);
    try std.testing.expectEqual(@as(f64, 50), route.amount_per_turn);
}

test "TradeSystem - delete route" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    const route_id = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    try std.testing.expectEqual(@as(usize, 1), trade.getRouteCount());

    const deleted = trade.deleteRoute(route_id);
    try std.testing.expect(deleted);
    try std.testing.expectEqual(@as(usize, 0), trade.getRouteCount());
}

test "TradeSystem - route status" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    const route_id = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    try std.testing.expectEqual(RouteStatus.active, trade.getRoute(route_id).?.status);

    trade.pauseRoute(route_id);
    try std.testing.expectEqual(RouteStatus.paused, trade.getRoute(route_id).?.status);

    trade.resumeRoute(route_id);
    try std.testing.expectEqual(RouteStatus.active, trade.getRoute(route_id).?.status);
}

test "TradeSystem - execute trade" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    // Setup markets
    trade.setBasePrice(.capital, .food, 100);
    trade.setStockpile(.farmland, .food, 1000);
    trade.setRegionDemand(.capital, .food, 200);

    // Create route
    _ = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    // Process turn
    const report = try trade.processTurn();

    try std.testing.expectEqual(@as(u32, 1), report.trades_executed);
    try std.testing.expectEqual(@as(f64, 50), report.total_amount);
    try std.testing.expect(report.total_revenue > 0);
    try std.testing.expectEqual(@as(u32, 1), report.shipments_departed);
}

test "TradeSystem - goods in transit" {
    var trade = TradeSystem(TestResource, TestRegion).initWithConfig(std.testing.allocator, .{
        .base_travel_time = 2.0, // 2 turns travel time
    });
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setStockpile(.farmland, .food, 1000);

    _ = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
        .distance = 1.0,
    });

    // Turn 0: Trade executed, goods depart
    _ = try trade.processTurn();
    try std.testing.expectEqual(@as(usize, 1), trade.getInTransitCount());

    // Turn 1: Goods still in transit
    _ = try trade.processTurn();
    try std.testing.expectEqual(@as(usize, 2), trade.getInTransitCount()); // New shipment + old

    // Turn 2: First shipment arrives
    const report = try trade.processTurn();
    try std.testing.expectEqual(@as(u32, 1), report.shipments_arrived);
}

test "TradeSystem - price updates with supply/demand" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setRegionDemand(.capital, .food, 100);
    trade.setStockpile(.capital, .food, 50); // Shortage

    trade.updatePrices();

    const market = trade.getMarket(.capital, .food);
    // With shortage, price should increase
    try std.testing.expect(market.current_price > 100);
}

test "TradeSystem - price decrease with surplus" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.farmland, .food, 100);
    trade.setRegionProduction(.farmland, .food, 200);
    trade.setRegionDemand(.farmland, .food, 50);

    trade.updatePrices();

    const market = trade.getMarket(.farmland, .food);
    // With surplus, price should decrease
    try std.testing.expect(market.current_price < 100);
}

test "TradeSystem - trade agreement tariffs" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    // Default tariff
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), trade.getTariffRate(.farmland, .capital), 0.001);

    // Create free trade agreement
    try trade.createAgreement(.farmland, .capital, .free_trade, 0, 0, null);

    try std.testing.expectApproxEqAbs(@as(f64, 0), trade.getTariffRate(.farmland, .capital), 0.001);
}

test "TradeSystem - trade embargo blocks routes" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setStockpile(.farmland, .food, 1000);
    trade.setBasePrice(.capital, .food, 100);

    const route_id = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    // Create embargo
    try trade.createAgreement(.farmland, .capital, .embargo, 0, 0, null);

    // Process turn - route should be blocked
    _ = try trade.processTurn();

    try std.testing.expectEqual(RouteStatus.blocked, trade.getRoute(route_id).?.status);
}

test "TradeSystem - trade not allowed during embargo" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    try trade.createAgreement(.farmland, .capital, .embargo, 0, 0, null);

    try std.testing.expect(!trade.isTradeAllowed(.farmland, .capital));
    try std.testing.expect(trade.isTradeAllowed(.farmland, .mining_town));
}

test "TradeSystem - agreement expiration" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    // Create agreement that expires in 2 turns
    try trade.createAgreement(.farmland, .capital, .free_trade, 0, 0, 2);

    try std.testing.expectEqual(@as(usize, 1), trade.getAgreements().len);

    // Process turns until expiration
    _ = try trade.processTurn(); // Turn 0 -> 1
    try std.testing.expectEqual(@as(usize, 1), trade.getAgreements().len);

    _ = try trade.processTurn(); // Turn 1 -> 2 (expires)
    try std.testing.expectEqual(@as(usize, 0), trade.getAgreements().len);
}

test "TradeSystem - insufficient supply" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setStockpile(.farmland, .food, 0); // No supply

    const route_id = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    _ = try trade.processTurn();

    try std.testing.expectEqual(RouteStatus.insufficient_supply, trade.getRoute(route_id).?.status);
}

test "TradeSystem - supply demand ratio" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setRegionProduction(.farmland, .food, 100);
    trade.setStockpile(.farmland, .food, 50);
    trade.setRegionDemand(.farmland, .food, 100);

    // Supply = 100 + 50 = 150, Demand = 100
    const ratio = trade.getSupplyDemandRatio(.farmland, .food);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), ratio, 0.01);
}

test "TradeSystem - stockpile management" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setStockpile(.capital, .food, 100);
    trade.setStorageCapacity(.capital, .food, 200);

    trade.addToStockpile(.capital, .food, 50);
    try std.testing.expectEqual(@as(f64, 150), trade.getMarket(.capital, .food).stockpile);

    // Try to add beyond capacity
    trade.addToStockpile(.capital, .food, 100);
    try std.testing.expectEqual(@as(f64, 200), trade.getMarket(.capital, .food).stockpile);

    // Remove from stockpile
    const removed = trade.removeFromStockpile(.capital, .food, 75);
    try std.testing.expectEqual(@as(f64, 75), removed);
    try std.testing.expectEqual(@as(f64, 125), trade.getMarket(.capital, .food).stockpile);
}

test "TradeSystem - trade history" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setStockpile(.farmland, .food, 1000);

    _ = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    _ = try trade.processTurn();
    _ = try trade.processTurn();
    _ = try trade.processTurn();

    const history = trade.getHistory();
    try std.testing.expectEqual(@as(usize, 3), history.len);

    const total_revenue = trade.getTotalRevenue();
    try std.testing.expect(total_revenue > 0);
}

test "TradeSystem - route priority" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setStockpile(.farmland, .food, 100);

    // Create two routes with different priorities
    _ = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 60,
        .priority = 50, // Lower priority
    });

    _ = try trade.createRoute(.{
        .source = .farmland,
        .destination = .port_city,
        .resource = .food,
        .amount_per_turn = 60,
        .priority = 150, // Higher priority
    });

    trade.setBasePrice(.port_city, .food, 100);

    // Only 100 available, higher priority route should execute first
    _ = try trade.processTurn();

    // Port city should have gotten goods first
    const history = trade.getHistory();
    try std.testing.expect(history.len >= 1);
    try std.testing.expectEqual(TestRegion.port_city, history[0].destination);
}

test "TradeSystem - transport cost calculation" {
    const RouteT = TradeRoute(TestResource, TestRegion);
    const route = RouteT{
        .id = 1,
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 100,
        .distance = 5.0,
        .terrain_modifier = 1.5,
    };

    const config = TradeConfig{
        .base_transport_cost = 0.1,
    };

    // Cost = 100 * 0.1 * 5.0 * 1.5 = 75
    const cost = route.getTransportCost(100, config);
    try std.testing.expectApproxEqAbs(@as(f64, 75), cost, 0.01);
}

test "TradeSystem - travel time calculation" {
    const RouteT = TradeRoute(TestResource, TestRegion);
    const route = RouteT{
        .id = 1,
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 100,
        .distance = 10.0,
        .terrain_modifier = 1.0,
    };

    const config = TradeConfig{
        .base_travel_time = 0.2,
    };

    // Time = 0.2 * 10.0 * 1.0 = 2.0 -> ceil = 2
    const time = route.getTravelTime(config);
    try std.testing.expectEqual(@as(u32, 2), time);
}

test "TradeSystem - reset" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setStockpile(.farmland, .food, 1000);
    _ = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });
    _ = try trade.processTurn();

    trade.reset();

    try std.testing.expectEqual(@as(usize, 0), trade.getRouteCount());
    try std.testing.expectEqual(@as(usize, 0), trade.getHistory().len);
    try std.testing.expectEqual(@as(u32, 0), trade.getCurrentTurn());
}

test "TradeSystem - production and consumption" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setStockpile(.farmland, .food, 100);
    trade.setRegionProduction(.farmland, .food, 50);
    trade.setRegionDemand(.farmland, .food, 30);

    _ = try trade.processTurn();

    // After turn: stockpile = 100 + 50 (production) - 30 (consumption) = 120
    try std.testing.expectEqual(@as(f64, 120), trade.getMarket(.farmland, .food).stockpile);
}

test "TradeSystem - average price" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setBasePrice(.farmland, .food, 80);
    trade.setBasePrice(.port_city, .food, 120);

    const avg = trade.getAveragePrice(.food);
    try std.testing.expectApproxEqAbs(@as(f64, 100), avg, 0.01);
}

test "TradeSystem - route count by status" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    _ = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    const route2 = try trade.createRoute(.{
        .source = .mining_town,
        .destination = .port_city,
        .resource = .ore,
        .amount_per_turn = 30,
    });

    trade.pauseRoute(route2);

    try std.testing.expectEqual(@as(usize, 1), trade.getRouteCountByStatus(.active));
    try std.testing.expectEqual(@as(usize, 1), trade.getRouteCountByStatus(.paused));
}

test "TradeSystem - auto adjust route" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setStockpile(.farmland, .food, 1000);
    trade.setStockpile(.capital, .food, 90);
    trade.setRegionDemand(.capital, .food, 100);

    // Create auto-adjusting route
    _ = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
        .auto_adjust = true,
    });

    // Destination needs only 10 (demand 100 - stockpile 90)
    _ = try trade.processTurn();

    const history = trade.getHistory();
    try std.testing.expect(history.len == 1);
    // Should have traded only 10 instead of 50
    try std.testing.expectApproxEqAbs(@as(f64, 10), history[0].amount, 0.01);
}

test "TradeSystem - route statistics" {
    var trade = TradeSystem(TestResource, TestRegion).init(std.testing.allocator);
    defer trade.deinit();

    trade.setBasePrice(.capital, .food, 100);
    trade.setStockpile(.farmland, .food, 1000);

    const route_id = try trade.createRoute(.{
        .source = .farmland,
        .destination = .capital,
        .resource = .food,
        .amount_per_turn = 50,
    });

    _ = try trade.processTurn();
    _ = try trade.processTurn();

    const route = trade.getRoute(route_id).?;
    try std.testing.expectApproxEqAbs(@as(f64, 100), route.total_traded, 0.01);
    try std.testing.expect(route.total_revenue > 0);
    try std.testing.expect(route.getProfit() > 0);
}
