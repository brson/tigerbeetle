const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.compstrat);

pub const Selection = enum {
    LeastTables,
    MostTables,

    LeastValues,
    MostValues,
    MidValues,

    HighTableValueRatio,
    LowTableValueRatio,

    MostTablesThenMostValues,
    MostTablesThenLeastValues,
    LeastTablesThenMostValues,
    LeastTablesThenLeastValues,

    MostFreeTablesThenHighTableValueRatio,
    MostFreeTablesThenLowTableValueRatio,
    LeastFreeTablesThenHighTableValueRatio,
    LeastFreeTablesThenLowTableValueRatio,
};

pub const Lookaround = enum {
    None,
    PostSelectionSingleTableNonFull,
    PostSelectionSingleTableLtHalfFull,
    PostSelectionSingleTableGtHalfFull,
    WithSelectionSingleTableNonFull,
    WithSelectionSingleTableLtHalfFull,
    WithSelectionSingleTableGtHalfFull,
};

pub const LookaroundPolicy = enum {
    NonFull,
    LtHalfFull,
    GtHalfFull,
};

pub const EagerMove = enum {
    None,
    AnyTable,
    FullTable,
    LtHalfFullTable,
    GtHalfFullTable,
};

pub const CompactionStats = struct {
    index_blocks_created: u64 = 0,
    index_blocks_released: u64 = 0,
    value_blocks_created: u64 = 0,
    value_blocks_released: u64 = 0,
    manifest_blocks_created: u64 = 0,
    manifest_blocks_released: u64 = 0,
    compactions_total: u64 = 0,
    compactions_move: u64 = 0,
};

const comp_select_var = "COMP_SELECT";
const comp_look_var = "COMP_LOOK";
const comp_move_var = "COMP_MOVE";

const comp_select_var_default = "TLEAST";
const comp_look_var_default = "NONE";
const comp_move_var_default = "NONE";

pub const CompStrat = struct {
    const Self = @This();

    select: Selection,
    look: Lookaround,
    move: EagerMove,

    select_str: []const u8,
    look_str: []const u8,
    move_str: []const u8,

    env_map: std.process.EnvMap,

    pub fn init(allocator: mem.Allocator) !*Self {
        // fixme
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator2 = gpa.allocator();
        var env_map = try std.process.getEnvMap(allocator2);
        errdefer env_map.deinit();

        var comp_select = Selection.LeastTables;
        var comp_look = Lookaround.None;
        var comp_move = EagerMove.None;

        const comp_select_str = env_map.get(comp_select_var) orelse comp_select_var_default;
        
        if (mem.eql(u8, comp_select_str, "TLEAST")) {
            comp_select = Selection.LeastTables;
        } else if (mem.eql(u8, comp_select_str, "TMOST")) {
            comp_select = Selection.MostTables;
        } else if (mem.eql(u8, comp_select_str, "VLEAST")) {
            comp_select = Selection.LeastValues;
        } else if (mem.eql(u8, comp_select_str, "VMOST")) {
            comp_select = Selection.MostValues;
        } else if (mem.eql(u8, comp_select_str, "VMID")) {
            comp_select = Selection.MidValues;
        } else if (mem.eql(u8, comp_select_str, "HIGH_TVR")) {
            comp_select = Selection.HighTableValueRatio;
        } else if (mem.eql(u8, comp_select_str, "LOW_TVR")) {
            comp_select = Selection.LowTableValueRatio;
        } else if (mem.eql(u8, comp_select_str, "TMOST_VMOST")) {
            comp_select = Selection.MostTablesThenMostValues;
        } else if (mem.eql(u8, comp_select_str, "TMOST_VLEAST")) {
            comp_select = Selection.MostTablesThenLeastValues;
        } else if (mem.eql(u8, comp_select_str, "TLEAST_VMOST")) {
            comp_select = Selection.LeastTablesThenMostValues;
        } else if (mem.eql(u8, comp_select_str, "TLEAST_VLEAST")) {
            comp_select = Selection.LeastTablesThenLeastValues;
        } else if (mem.eql(u8, comp_select_str, "TMFREE_HIGH_TVR")) {
            comp_select = Selection.MostFreeTablesThenHighTableValueRatio;
        } else if (mem.eql(u8, comp_select_str, "TMFREE_LOW_TVR")) {
            comp_select = Selection.MostFreeTablesThenLowTableValueRatio;
        } else if (mem.eql(u8, comp_select_str, "TLFREE_HIGH_TVR")) {
            comp_select = Selection.LeastFreeTablesThenHighTableValueRatio;
        } else if (mem.eql(u8, comp_select_str, "TLFREE_LOW_TVR")) {
            comp_select = Selection.LeastFreeTablesThenLowTableValueRatio;
        } else {
            @panic("bad COMP_SELECT");
        }

        const comp_look_str = env_map.get(comp_look_var) orelse comp_look_var_default;
        if (mem.eql(u8, comp_look_str, "NONE")) {
            comp_look = Lookaround.None;
        } else if (mem.eql(u8, comp_look_str, "POST_SINGLE_NONFULL")) {
            comp_look = Lookaround.PostSelectionSingleTableNonFull;
        } else if (mem.eql(u8, comp_look_str, "POST_SINGLE_LTHALF")) {
            comp_look = Lookaround.PostSelectionSingleTableLtHalfFull;
        } else if (mem.eql(u8, comp_look_str, "POST_SINGLE_GTTHALF")) {
            comp_look = Lookaround.PostSelectionSingleTableGtHalfFull;
        } else if (mem.eql(u8, comp_look_str, "WITH_SINGLE_NONFULL")) {
            comp_look = Lookaround.WithSelectionSingleTableNonFull;
        } else if (mem.eql(u8, comp_look_str, "WITH_SINGLE_LTHALF")) {
            comp_look = Lookaround.WithSelectionSingleTableLtHalfFull;
        } else if (mem.eql(u8, comp_look_str, "WITH_SINGLE_GTHALF")) {
            comp_look = Lookaround.WithSelectionSingleTableGtHalfFull;
        } else {
            @panic("bad COMP_LOOK");
        }

        const comp_move_str = env_map.get(comp_move_var) orelse comp_move_var_default;
        if (mem.eql(u8, comp_move_str, "NONE")) {
            comp_move = EagerMove.None;
        } else if (mem.eql(u8, comp_move_str, "ANY")) {
            comp_move = EagerMove.AnyTable;
        } else if (mem.eql(u8, comp_move_str, "FULL")) {
            comp_move = EagerMove.FullTable;
        } else if (mem.eql(u8, comp_move_str, "LTHALF")) {
            comp_move = EagerMove.GtHalfFullTable;
        } else if (mem.eql(u8, comp_move_str, "GTHALF")) {
            comp_move = EagerMove.GtHalfFullTable;
        } else {
            @panic("bad COMP_MOVE");
        }

        std.log.info("{s} = {s}", .{
            comp_select_var,
            comp_select_str,
        });
        std.log.info("{s} = {s}", .{
            comp_look_var,
            comp_look_str,
        });
        std.log.info("{s} = {s}", .{
            comp_move_var,
            comp_move_str,
        });

        const compstrat = try allocator.create(CompStrat);
        compstrat.* = CompStrat {
            .select = comp_select,
            .look = comp_look,
            .move = comp_move,
            .select_str = comp_select_str,
            .look_str = comp_look_str,
            .move_str = comp_move_str,
            .env_map = env_map,
        };
        return compstrat;
    }

    pub fn deinit(self: *Self, allocator: mem.Allocator) void {
        self.env_map.deinit();
        allocator.destroy(self);
    }

    pub fn log_final_stats(
        self: *const Self,
        compaction_stats: *const CompactionStats
    ) void {
        const blocks_created = compaction_stats.index_blocks_created
            + compaction_stats.value_blocks_created
            + compaction_stats.manifest_blocks_created;
        const blocks_released = compaction_stats.index_blocks_released
            + compaction_stats.value_blocks_released
            + compaction_stats.manifest_blocks_released;
        const active_blocks = blocks_created -| blocks_released;

        log.info(
            "compaction stats:\n" ++
                "index_blocks_created: {}\n" ++
                "index_blocks_released: {}\n" ++
                "value_blocks_created: {}\n" ++
                "value_blocks_released: {}\n" ++
                "manifest_blocks_created: {}\n" ++
                "manifest_blocks_released: {}\n" ++
                "total_blocks_created: {}\n" ++
                "total_blocks_released: {}\n" ++
                "active_blocks: {}\n" ++
                "compactions_total: {}\n" ++
                "compactions_move: {}",
            .{
                compaction_stats.index_blocks_created,
                compaction_stats.index_blocks_released,
                compaction_stats.value_blocks_created,
                compaction_stats.value_blocks_released,
                compaction_stats.manifest_blocks_created,
                compaction_stats.manifest_blocks_released,
                blocks_created,
                blocks_released,
                active_blocks,
                compaction_stats.compactions_total,
                compaction_stats.compactions_move,
            },
        );

        log.info("\n~compaction-stats~\nC_{s}_L_{s}_M_{s}, {}, {}, {}, {}", .{
            self.select_str,
            self.look_str,
            self.move_str,
            blocks_created,
            active_blocks,
            compaction_stats.compactions_total,
            compaction_stats.compactions_move,
        });
    }

    pub fn pick_table_candidate(
        self: *const Self,
        comptime LeastOverlapTable: type,
        old: *const LeastOverlapTable,
        new: *const LeastOverlapTable,
        comptime TableInfo: type,
    ) *const LeastOverlapTable {
        const old_table_count = old.range.tables.count() + 1;
        const old_value_count = old.table.table_info.value_count + old.range.value_count;
        const new_table_count = new.range.tables.count() + 1;
        const new_value_count = new.table.table_info.value_count + new.range.value_count;

        const old_ratio = @as(f32, @floatFromInt(old_table_count))
            / @as(f32, @floatFromInt(old_value_count));
        const new_ratio = @as(f32, @floatFromInt(new_table_count))
            / @as(f32, @floatFromInt(new_value_count));

        const old_table_max_values = old_table_count * TableInfo.value_count_max_actual;
        const new_table_max_values = new_table_count * TableInfo.value_count_max_actual;
        const old_free_values = old_table_max_values - old_value_count;
        const old_free_tables = @divFloor(old_free_values, TableInfo.value_count_max_actual);
        const new_free_values = new_table_max_values - new_value_count;
        const new_free_tables = @divFloor(new_free_values, TableInfo.value_count_max_actual);

        const old_table_mid_values = @divFloor(old_table_max_values, 2);
        const new_table_mid_values = @divFloor(new_table_max_values, 2);
        const old_mid_value_vicinity = @abs(
            @as(i64, @intCast(old_value_count)) -
                @as(i64, @intCast(old_table_mid_values))
        );
        const new_mid_value_vicinity = @abs(
            @as(i64, @intCast(new_value_count)) -
                @as(i64, @intCast(new_table_mid_values))
        );

        const new_best = switch (self.select) {
            Selection.LeastTables => (
                new_table_count < old_table_count
            ),
            Selection.MostTables => (
                new_table_count > old_table_count
            ),
            Selection.LeastValues => (
                new_value_count < old_value_count
            ),
            Selection.MostValues => (
                new_value_count > old_value_count
            ),
            Selection.MidValues => (
                new_mid_value_vicinity < old_mid_value_vicinity
            ),
            Selection.HighTableValueRatio => (
                new_ratio > old_ratio
            ),
            Selection.LowTableValueRatio => (
                new_ratio < old_ratio
            ),
            Selection.MostTablesThenMostValues => brk: {
                if (old_free_tables != new_free_tables) {
                    break :brk new_table_count > old_table_count;
                } else {
                    break :brk new_value_count > old_value_count;
                }
            },
            Selection.MostTablesThenLeastValues => brk: {
                if (old_free_tables != new_free_tables) {
                    break :brk new_table_count > old_table_count;
                } else {
                    break :brk new_value_count < old_value_count;
                }
            },
            Selection.LeastTablesThenMostValues => brk: {
                if (old_free_tables != new_free_tables) {
                    break :brk new_table_count < old_table_count;
                } else {
                    break :brk new_value_count > old_value_count;
                }
            },
            Selection.LeastTablesThenLeastValues => brk: {
                if (old_free_tables != new_free_tables) {
                    break :brk new_table_count < old_table_count;
                } else {
                    break :brk new_value_count < old_value_count;
                }
            },
            Selection.MostFreeTablesThenHighTableValueRatio => brk: {
                if (old_free_tables != new_free_tables) {
                    break :brk new_free_tables > old_free_tables;
                } else {
                    break :brk new_ratio > old_ratio;
                }
            },
            Selection.MostFreeTablesThenLowTableValueRatio => brk: {
                if (old_free_tables != new_free_tables) {
                    break :brk new_free_tables > old_free_tables;
                } else {
                    break :brk new_ratio < old_ratio;
                }
            },
            Selection.LeastFreeTablesThenHighTableValueRatio => brk: {
                if (old_free_tables != new_free_tables) {
                    break :brk new_free_tables < old_free_tables;
                } else {
                    break :brk new_ratio > old_ratio;
                }
            },
            Selection.LeastFreeTablesThenLowTableValueRatio => brk: {
                if (old_free_tables != new_free_tables) {
                    break :brk new_free_tables < old_free_tables;
                } else {
                    break :brk new_ratio < old_ratio;
                }
            },
        };

        if (new_best) {
            return new;
        } else {
            return old;
        }
    }

    pub fn with_lookaround_policy(self: *const Self) ?LookaroundPolicy {
        return switch (self.look) {
            Lookaround.None => null,
            Lookaround.PostSelectionSingleTableNonFull => null,
            Lookaround.PostSelectionSingleTableLtHalfFull => null,
            Lookaround.PostSelectionSingleTableGtHalfFull => null,
            Lookaround.WithSelectionSingleTableNonFull => LookaroundPolicy.NonFull,
            Lookaround.WithSelectionSingleTableLtHalfFull => LookaroundPolicy.LtHalfFull,
            Lookaround.WithSelectionSingleTableGtHalfFull => LookaroundPolicy.GtHalfFull,
        };
    }

    pub fn post_lookaround_policy(self: *const Self) ?LookaroundPolicy {
        return switch (self.look) {
            Lookaround.None => null,
            Lookaround.PostSelectionSingleTableNonFull => LookaroundPolicy.NonFull,
            Lookaround.PostSelectionSingleTableLtHalfFull => LookaroundPolicy.LtHalfFull,
            Lookaround.PostSelectionSingleTableGtHalfFull => LookaroundPolicy.GtHalfFull,
            Lookaround.WithSelectionSingleTableNonFull => null,
            Lookaround.WithSelectionSingleTableLtHalfFull => null,
            Lookaround.WithSelectionSingleTableGtHalfFull => null,
        };
    }
};

