const std = @import("std");

fn getNextPtrWrapping(capacity: u32, startPtr: u32, endPtr: u32) error{OutOfMemory}!u32 {
    if (startPtr <= endPtr) {
        if (endPtr < capacity - 1) {
            return endPtr + 1;
        } else {
            if (startPtr > 0) {
                return 0;
            } else return error.OutOfMemory;
        }
    } else {
        if (endPtr + 1 >= startPtr) return error.OutOfMemory else return endPtr + 1;
    }
}

fn getPreviousPointerWrapping(capacity: u32, startPtr: u32, endPtr: u32) u32 {
    if (startPtr < endPtr) {
        if (endPtr == startPtr) return startPtr;
    } else {
        if (endPtr == 0) {
            return capacity;
        } else return endPtr - 1;
    }

    return 0;
}

fn getNextStartPoiter(capacity: u32, startPtr: u32, endPtr: u32) error{OutOfMemory}!u32 {
    if (startPtr >= endPtr) {
        if (startPtr < capacity) {
            return startPtr + 1;
        } else {
            if (endPtr > 0) {
                return 0;
            } else return error.OutOfMemory;
        }
    } else {
        if (startPtr >= endPtr) return error.OutOfMemory else return startPtr + 1;
    }
}

pub fn FixedSizeScrollingQueue(T: type, capacity: comptime_int) type {
    return struct {
        const Self = @This();

        startPtr: u32 = 0,
        endPtr: u32 = 0,
        data: [capacity]T = undefined,
        capacity: u32 = capacity,

        pub fn add(self: *Self, item: T) error{OutOfMemory}!void {
            const nextPtr = try getNextPtrWrapping(capacity, self.startPtr, self.endPtr);

            self.data[self.endPtr] = item;
            self.endPtr = nextPtr;
        }

        pub fn pop(self: *Self) error{OutOfMemory}! T {
            const newEndPtr = try getNextStartPoiter(capacity, self.startPtr, self.endPtr);
            const res = self.data[self.startPtr];
            self.startPtr = newEndPtr;
            return res;
        }

        pub fn first(self: *Self) ?T {
            if (self.getSize() == 0) return null;
            return self.data[self.startPtr];
        }

        pub fn last(self: *Self) ?T {
            if (self.getSize() == 0) return null;
            return self.data[self.endPtr - 1];
        }

        pub fn getCapacity(self: *Self) u32 {
            return self.capacity;
        }

        pub fn getSize(self: *Self) u32 {
            if (self.endPtr == self.startPtr) {return 0;}
            else if (self.endPtr > self.startPtr) { return self.endPtr - self.startPtr; }
            else { return self.capacity - self.startPtr + self.endPtr; }
        }

        pub fn toSlice(self: *Self, allocator: *const std.mem.Allocator) ![]T {
            const queueSize = self.getSize();

            const slice = try allocator.alloc(T, queueSize);
            @memset(@as([]u32, @ptrCast(slice)), 0);

            if (self.endPtr > self.startPtr) { 
                @memcpy(slice[0..queueSize], self.data[self.startPtr..self.endPtr]); 
            }

            else if (self.endPtr < self.startPtr) {
                const upperSectionSize = self.capacity - self.startPtr;

                @memcpy(slice[0..upperSectionSize], self.data[self.startPtr..self.capacity]);
                @memcpy(slice[upperSectionSize..queueSize], self.data[0..self.endPtr]);
            }

            return slice;
        }

        pub fn init() Self {
            return .{};
        }

        pub fn indices(self: *Self) []u32 {
            // note to self: attempting to quadratically iterate over a queue will end in major dick pain. 
            // THis is allocated on the stack. IF you attempt to iterate ^2 it will override one of the values. 
            // so reminder to copy if desired.
            var result: [capacity]u32 = [_] u32{0} ** capacity;

            const _size = self.getSize();
            for (0.._size) |idx| {
                result[idx] = @mod(self.startPtr + @as(u32, @intCast(idx)), capacity);
            }
            
            return result[0.._size];
        }

        pub fn empty(self: *Self) void {
            self.endPtr = 0;
            self.startPtr = 0;
        }
    };
}

test "FixedSizeScrollingBuffer" {
    const expect = std.testing.expect;
    const allocator = std.heap.page_allocator;

    var queue = FixedSizeScrollingQueue(u32, 10).init();

    try queue.add(32);
    try queue.add(64);

    std.debug.print("\n{any}\n", .{queue.data});

    const first = queue.first();
    const last = queue.last();
    std.debug.print("first {} from queue.\n", .{first});
    std.debug.print("last {} from queue.\n", .{last});

    try expect(first == 32);
    try expect(last == 64);

    const poppedValue = try queue.pop();
    std.debug.print("Popped {} from queue. \n", .{poppedValue});
    try expect(poppedValue == 32);
    try expect(queue.first() == 64);

    std.debug.print("{} {} \n", .{queue.startPtr, queue.endPtr});
    const poppedValue2 = try queue.pop();
    std.debug.print("Popped {} from queue. \n", .{poppedValue});
    try expect(poppedValue2 == 64);

    try queue.add(1);
    try queue.add(2);
    try queue.add(3);
    try queue.add(4);
    try queue.add(5);
    try queue.add(6);
    try queue.add(7);

    const slice = try queue.toSlice(&allocator);
    defer allocator.free(slice);

    std.debug.print("\n{any}\n", .{queue.data});
    try expect( std.mem.eql(u32, slice, &([_]u32{1, 2, 3, 4, 5, 6, 7})) );
    
    try queue.add(8);
    try queue.add(9);

    std.debug.print("\n{any}\n", .{queue.data});

    queue.add(10) catch |err| {
        try expect(err == error.OutOfMemory);
    };

    try expect(try queue.pop() == 1);
    try queue.add(10);

    const slice2 = try queue.toSlice(&allocator);
    defer allocator.free(slice2);

    std.debug.print("\n{any}\n", .{queue.data});
    std.debug.print("\n{any}\n", .{slice2});

    try expect(std.mem.eql(u32, slice2, &([_]u32{2, 3, 4, 5, 6, 7, 8, 9, 10})));
}
