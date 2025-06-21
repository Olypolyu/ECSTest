const std = @import("std");
const builtin = @import("builtin");
const android = @import("android");
const CrappyBird = @import("./crappy_bird.zig");
pub fn main() !void {
    return CrappyBird.main();
}

/// custom panic handler for Android
pub const panic =
    if (builtin.abi.isAndroid()) android.panic else std.debug.FullPanic(std.debug.defaultPanic);

/// custom standard options for Android
pub const std_options: std.Options =
    if (builtin.abi.isAndroid()) .{
        .logFn = android.logFn,
    } else .{};

comptime {
    if (builtin.abi.isAndroid()) {
        // Setup exported C-function as defined in AndroidManifest.xml
        // ie. <meta-data android:name="android.app.lib_name" android:value="main"/>
        @export(&androidMain, .{ .name = "main" });
    }
}

fn androidMain() callconv(.c) c_int {
    return std.start.callMain();
}
