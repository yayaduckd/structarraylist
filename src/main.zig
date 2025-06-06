const std = @import("std");
const testing = std.testing;

pub fn VecList(comptime T: type) type {
    return struct {
        const Self = @This();
        const Allocator = std.mem.Allocator;

        items: []T,
        capacity: usize,
        alloc: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .capacity = 0,
                .items = allocator.alloc(T, 0) catch unreachable,
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

fn StructVecList(comptime T: type) type {
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
            var newStruct = Self{
                .alloc = alloc,
                .list = undefined,
                .capacity = 0,
                .length = 0,
            };
            inline for (info.fields) |field| {
                const field_name = field.name;
                @field(newStruct.list, field_name) = @TypeOf(@field(newStruct.list, field_name)).init(alloc);
            }
            return newStruct;
        }

        pub fn deinit(self: *Self) void {
            inline for (info.fields) |field| {
                const field_name = field.name;
                @field(self.list, field_name).deinit();
            }
        }

        pub fn append(self: *Self, item: T) !void {
            inline for (info.fields) |field| {
                const field_name = field.name;
                try @field(self.list, field_name).append(@field(item, field_name));
            }
        }

        pub fn get_elem(self: *Self, index: usize) T {
            var t: T = undefined;
            inline for (info.fields) |field| {
                const field_name = field.name;
                @field(t, field_name) = @field(self.list, field_name).items[index];
            }
            return t;
        }

        pub fn get_attribute(self: *Self, comptime attribute_name: []const u8) @TypeOf(@field(self.list, attribute_name).items) {
            return @field(self.list, attribute_name).items;
        }
    };
}

var rng = std.Random.DefaultPrng.init(0);
const rand = rng.random();

const TestStruct = struct {
    a: u32,
    b: f64,
    c: c_char,
    d: [15]usize,

    pub fn get_random() TestStruct {
        var s = TestStruct{
            .a = rand.int(u32),
            .b = rand.float(f64),
            .c = rand.int(c_char),
            .d = undefined,
        };

        var ptr: [15 * @sizeOf(usize)]u8 = @bitCast(s.d);
        rand.bytes(&ptr);
        s.d = @bitCast(ptr);
        return s;
    }

    pub fn eql(self: TestStruct, other: TestStruct) bool {
        var equal = self.a == other.a and self.b == other.b and self.c == other.c;
        for (self.d, other.d) |a, b| {
            equal = equal and a == b;
        }
        return equal;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var vec = VecList(u32).init(alloc);
    try vec.append(2);
    try vec.append(3);
    try vec.append(1231);

    for (vec.items) |item| {
        std.log.debug("{d}", .{item});
    }

    var svl = StructVecListReal(TestStruct).init(alloc);
    // a.init(alloc);
    const a = TestStruct.get_random();
    std.log.debug("{}", .{a});

    try svl.append(a);
    const b = svl.get_elem(0);
    const bat = svl.get_attribute("a");
    std.log.debug("{any}", .{bat});
    try testing.expect(a.eql(b));

    svl.deinit();
    // _ = a;
    vec.deinit();

    _ = gpa.deinit();
}

test "basic add functionality" {
    try testing.expect(3 + 7 == 10);
}
