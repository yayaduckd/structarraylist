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

        pub fn delete(self: *Self, index: usize) void {
            // @memcpy(self.items[index .. self.items.len - 1], self.items[index + 1 .. self.items.len]);
            for (self.items[index + 1 .. self.items.len], index + 1..) |item, i| {
                self.items[i - 1] = item;
            }
            // self.items = self.items[0..self.item]
            self.items.len -= 1;
        }

        pub fn deinit(self: *Self) void {
            var free: []T = undefined;
            free.ptr = self.items.ptr;
            free.len = self.capacity;
            self.alloc.free(free);
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
            self.length += 1;
        }

        pub fn delete(self: *Self, index: usize) void {
            inline for (info.fields) |field| {
                const field_name = field.name;
                @field(self.list, field_name).delete(index);
            }
            self.length -= 1;
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
test "VecList: init, append, deinit" {
    const allocator = testing.allocator;
    var list = VecList(i32).init(allocator);
    defer list.deinit();

    try testing.expectEqual(@as(usize, 0), list.items.len);
    try testing.expectEqual(@as(usize, 0), list.capacity);

    try list.append(10);
    try testing.expectEqual(@as(usize, 1), list.items.len);
    try testing.expectEqual(@as(i32, 10), list.items[0]);

    try list.append(20);
    try testing.expectEqual(@as(usize, 2), list.items.len);
    try testing.expectEqual(@as(i32, 10), list.items[0]);
    try testing.expectEqual(@as(i32, 20), list.items[1]);

    // This will trigger a few reallocations due to the inefficient growth strategy
    try list.append(30);
    try list.append(40);
    try testing.expectEqual(@as(usize, 4), list.items.len);
    try testing.expectEqualSlices(i32, &.{ 10, 20, 30, 40 }, list.items);
}

test "VecList: delete" {
    const allocator = testing.allocator;
    var list = VecList(u8).init(allocator);
    defer list.deinit();

    try list.append('a');
    try list.append('b');
    try list.append('c');
    try list.append('d');
    try list.append('e');

    // Expected state: ['a', 'b', 'c', 'd', 'e'], len=5
    try testing.expectEqualSlices(u8, "abcde", list.items);

    // Delete from middle
    list.delete(2); // delete 'c'
    try testing.expectEqual(@as(usize, 4), list.items.len);
    try testing.expectEqualSlices(u8, &.{ 'a', 'b', 'd', 'e' }, list.items[0..4]);

    // Delete from start
    list.delete(0); // delete 'a'
    try testing.expectEqual(@as(usize, 3), list.items.len);
    try testing.expectEqualSlices(u8, &.{ 'b', 'd', 'e' }, list.items[0..3]);

    // Delete from end
    list.delete(2); // delete 'e'
    try testing.expectEqual(@as(usize, 2), list.items.len);
    try testing.expectEqualSlices(u8, &.{ 'b', 'd' }, list.items[0..2]);

    // Delete until empty
    list.delete(0);
    list.delete(0);
    try testing.expectEqual(@as(usize, 0), list.items.len);

    // Test append after being emptied
    try list.append('z');
    try testing.expectEqual(@as(usize, 1), list.items.len);
    try testing.expectEqualSlices(u8, "z", list.items);
}

// A simpler struct for testing StructVecListReal without the complexity
// of random data or large arrays.
const TestStructForTest = struct {
    a: u32,
    b: bool,

    pub fn eql(self: @This(), other: @This()) bool {
        return self.a == other.a and self.b == other.b;
    }
};

test "StructVecListReal: init, append, get_elem" {
    const allocator = testing.allocator;
    var svl = StructVecListReal(TestStructForTest).init(allocator);
    defer svl.deinit();

    // Check initial state
    try testing.expectEqual(@as(usize, 0), svl.length);
    try testing.expectEqual(@as(usize, 0), svl.list.a.items.len);
    try testing.expectEqual(@as(usize, 0), svl.list.b.items.len);

    const s1 = TestStructForTest{ .a = 100, .b = true };
    const s2 = TestStructForTest{ .a = 200, .b = false };

    try svl.append(s1);
    try testing.expectEqual(@as(usize, 1), svl.length);

    // Retrieve and check
    const s1_retrieved = svl.get_elem(0);
    try testing.expect(s1.eql(s1_retrieved));

    try svl.append(s2);
    try testing.expectEqual(@as(usize, 2), svl.length);

    // Retrieve and check again
    const s2_retrieved = svl.get_elem(1);
    try testing.expect(s2.eql(s2_retrieved));
    // also check the first one is still there
    const s1_retrieved_again = svl.get_elem(0);
    try testing.expect(s1.eql(s1_retrieved_again));
}

test "StructVecListReal: get_attribute" {
    const allocator = testing.allocator;
    var svl = StructVecListReal(TestStructForTest).init(allocator);
    defer svl.deinit();

    const s1 = TestStructForTest{ .a = 100, .b = true };
    const s2 = TestStructForTest{ .a = 200, .b = false };
    const s3 = TestStructForTest{ .a = 300, .b = true };

    try svl.append(s1);
    try svl.append(s2);
    try svl.append(s3);

    const a_slice = svl.get_attribute("a");
    const b_slice = svl.get_attribute("b");

    try testing.expectEqualSlices(u32, &.{ 100, 200, 300 }, a_slice);
    try testing.expectEqualSlices(bool, &.{ true, false, true }, b_slice);
}

test "StructVecListReal: delete" {
    const allocator = testing.allocator;
    var svl = StructVecListReal(TestStructForTest).init(allocator);
    defer svl.deinit();

    const s1 = TestStructForTest{ .a = 10, .b = true };
    const s2 = TestStructForTest{ .a = 20, .b = false };
    const s3 = TestStructForTest{ .a = 30, .b = true };
    const s4 = TestStructForTest{ .a = 40, .b = false };

    try svl.append(s1);
    try svl.append(s2);
    try svl.append(s3);
    try svl.append(s4);

    // State: [s1, s2, s3, s4], len=4
    try testing.expectEqual(@as(usize, 4), svl.length);

    // Delete from middle (s3 at index 2)
    svl.delete(2);
    try testing.expectEqual(@as(usize, 3), svl.length);

    // Check that s4 is now at index 2
    const s4_retrieved = svl.get_elem(2);
    try testing.expect(s4.eql(s4_retrieved));
    // Check that an earlier element is unaffected
    const s2_retrieved = svl.get_elem(1);
    try testing.expect(s2.eql(s2_retrieved));

    // Check attributes view is correct
    const a_slice = svl.get_attribute("a");
    try testing.expectEqualSlices(u32, &.{ 10, 20, 40 }, a_slice);

    // Delete from beginning
    svl.delete(0); // delete s1
    try testing.expectEqual(@as(usize, 2), svl.length);
    const s2_now_at_start = svl.get_elem(0);
    try testing.expect(s2.eql(s2_now_at_start));
    const b_slice = svl.get_attribute("b");
    try testing.expectEqualSlices(bool, &.{ false, false }, b_slice);
}
