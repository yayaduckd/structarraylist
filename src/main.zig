const std = @import("std");
const testing = std.testing;

pub fn VecList(comptime T: type) type {
    return struct {
        const Self = @This();
        const Allocator = std.mem.Allocator;

        items: []T,
        capacity: usize,
        alloc: Allocator,

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .capacity = 0,
                .items = try allocator.alloc(T, 0),
                .alloc = allocator,
            };
        }

        pub fn ensure_capacity(self: *Self) !void {
            if (self.capacity >= self.items.len) return;
            var new_items = try self.alloc.alloc(T, self.items.len);
            @memcpy(new_items[0..self.capacity], self.items[0..self.capacity]);
            self.alloc.free(self.items[0..self.capacity]);
            self.capacity = new_items.len;

            self.items = new_items;
        }

        pub fn append(self: *Self, item: T) !void {
            self.items.len += 1;
            try self.ensure_capacity();
            self.items[self.items.len - 1] = item;
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.items);
        }
    };
}

pub fn StructVecList(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @panic("you just posted cringe...");
    }
    // T is a struct
    const count = info.@"struct".fields.len;
    var fields: [count]std.builtin.Type.StructField = undefined;
    var new_info: std.builtin.Type.Struct = undefined;
    // new_info.@"struct".fields = []
    // const lists:
    var i: usize = 0;
    // var buf: [32]u8 = undefined;
    inline for (info.@"struct".fields) |field| {
        const field_type = field.type;
        const field_name = field.name;

        // recurse into sub-structs
        const list = VecList(field_type);
        fields[i].type = list;
        fields[i].name = field_name;
        fields[i].default_value_ptr = null;
        fields[i].is_comptime = false;
        fields[i].alignment = @alignOf(list);
        i += 1;
    }

    new_info.fields = &fields;
    new_info.backing_integer = null;
    new_info.decls = &[0]std.builtin.Type.Declaration{};
    new_info.is_tuple = false;
    new_info.layout = std.builtin.Type.ContainerLayout.auto;

    const new_info_final: std.builtin.Type = .{ .@"struct" = new_info };

    return @Type(new_info_final);
}

pub fn StructVecListReal(comptime T: type) type {
    return struct {
        const Self = @This();
        const info = @typeInfo(T).@"struct";

        list: StructVecList(T),
        alloc: std.mem.Allocator,
        capacity: usize,
        length: usize,

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .alloc = alloc,
                .list = undefined,
                .capacity = 0,
                .length = 0,
            };
        }

        pub fn append(self: *Self, item: T) !void {
            inline for (info.fields) |field| {
                const field_name = field.name;
                try @field(self.list, field_name).append(@field(item, field_name));
            }
        }
    };
}

// const StructVecListReal = struct {
//     list: StructVecList(comptime T: type)
// };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var vec = try VecList(u32).init(alloc);
    try vec.append(2);
    try vec.append(3);
    try vec.append(1231);

    for (vec.items) |item| {
        std.log.debug("{d}", .{item});
    }

    vec.deinit();

    var a = StructVecListReal(VecList(u32)).init(alloc);
    // a.init(alloc);
    try a.append(vec);
    // _ = a;

    _ = gpa.deinit();
}

test "basic add functionality" {
    try testing.expect(3 + 7 == 10);
}
