const std = @import("std");
const builtin = @import("builtin");
const android = @import("android");
const rl = @import("raylib");

const pipeWidth = 80;
const pipeLipWitdh = pipeWidth + 20;
const pipeLipHeight = 30;

const Pipe = struct {
    position: rl.Vector2,
    up: bool = false,
};

const maxSpeed = 8;
const jumpVec = rl.Vector2.init(0, -3);
const gravity = rl.Vector2.init(0, 0.1);

const Bird = struct {
    position: rl.Vector2,
    speed: rl.Vector2,
    isDead: bool = false,

    fn getCollisionBox(self: Bird) rl.Rectangle {
        return rl.Rectangle.init(self.position.x, self.position.y, 40, 40);
    }
};

var touchLast = false;

fn birdShouldJump() bool {
    const touch = rl.getTouchPointCount() > 0;
    const touched = touch != touchLast;
    touchLast = touch;

    std.log.info("toched: {} \nTouchLast: {} \nTouch: {} \n", .{ touched, touchLast, touch });

    return rl.isMouseButtonPressed(rl.MouseButton.left) or
        rl.isMouseButtonPressed(rl.MouseButton.right) or
        rl.isKeyPressed(rl.KeyboardKey.space) or
        touched;
}

const GameScreen = enum {
    GAME,
    GAMEOVER,
    MENU,
};

const GameState = struct {
    rand: std.Random,
    allocator: std.mem.Allocator,
    arenaAlloc: ?*const std.mem.Allocator = null,

    screen: GameScreen,

    screenHeight: u32 = 0,
    screenWidth: u32 = 0,

    distance: u32 = 0,
    speed: f32 = 1,
    score: u32,
    bird: Bird,

    pipes: *std.ArrayList(Pipe),
    currentPipeCollisions: ?[]rl.Rectangle = null,
    lastPipeDistance: u32 = 0,

    pub fn getArena(self: GameState) error{OutOfMemory}!*const std.mem.Allocator {
        if (self.arenaAlloc) |_arenaAlloc| return _arenaAlloc else return error.OutOfMemory;
    }

    fn init(allocator: std.mem.Allocator, rand: std.Random, pipes: *std.ArrayList(Pipe)) GameState {
        return .{
            .allocator = allocator,
            .rand = rand,

            .screen = GameScreen.GAME,

            .score = 0,
            .distance = 0,
            .pipes = pipes,

            .bird = .{ .speed = rl.Vector2{ .x = 0, .y = 0 }, .position = rl.Vector2.init(64, 450 / 2) },
        };
    }

    fn restart(self: GameState) GameState {
        self.pipes.clearAndFree();
        return GameState.init(self.allocator, self.rand, self.pipes);
    }
};

// okay, so each pipe needs a position and a bounding box,
// the bird needs a position a bounding box and a texture.
// i guess i will have a bird and a array of pipes.

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const screenWidth = 800;
    const screenHeight = 450;

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(screenWidth, screenHeight, "Crappy Bird");
    defer rl.closeWindow();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const rand = prng.random();

    var pipes = std.ArrayList(Pipe).init(allocator);

    var state = GameState.init(allocator, rand, &pipes);

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);

        state.screenHeight = @intCast(rl.getScreenHeight());
        state.screenWidth = @intCast(rl.getScreenWidth());
        state.arenaAlloc = &arena.allocator();

        try doGameLogic(&state);
        try PaintScreen(&state);

        if (state.bird.isDead) {
            state = state.restart();
        }

        arena.deinit();
        state.currentPipeCollisions = null;
    }
}

fn makePipeCollisions(pipes: *[]Pipe, arena: *const std.mem.Allocator) ?[]rl.Rectangle {
    // creates a array containing the collisions for every pipe according to state.
    // Should be called every frame. The array is detroyed afterwards.

    if (pipes.len == 0) return null;

    var pipeCollisions =
        arena.alloc(rl.Rectangle, pipes.len) catch @panic("Couldn't allocate memory.");

    const height: f32 = @floatFromInt(rl.getScreenHeight());

    for (pipes.*, 0..) |pipe, idx| {
        pipeCollisions[idx] = (if (pipe.up) rl.Rectangle.init(pipe.position.x, 0, pipeWidth, pipe.position.y) else rl.Rectangle.init(pipe.position.x, pipe.position.y, pipeWidth, height - pipe.position.y));
    }

    return pipeCollisions;
}

test "makePipeCollisions" {
    const pipes = [_]Pipe{
        .{ .position = rl.Vector2.init(0, 15), .up = false },
        .{ .position = rl.Vector2.init(1, 10), .up = false },
        .{ .position = rl.Vector2.init(2, 20), .up = false },
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const collisions = makePipeCollisions(&pipes, &arena.allocator());
    _ = collisions;

    const expect = std.testing.expect;

    try expect(false);
}

fn attemptMakeNewPipe(state: *GameState) void {
    const width: f32 = @floatFromInt(rl.getScreenWidth());
    const height: f32 = @floatFromInt(rl.getScreenHeight());

    const amountBeforePipe = 300;

    if ((state.distance - state.lastPipeDistance) >= amountBeforePipe) {
        state.lastPipeDistance = state.distance;

        const openingLength = @max((height * 0.75) * state.rand.float(f32), height * 0.25);
        const openingDistanceGround = (height - openingLength) * state.rand.float(f32);

        state.pipes.append(Pipe{ .position = rl.Vector2.init(
            @floor(width),
            @floor(height - openingDistanceGround),
        ), .up = false }) catch @panic("cannot allocate memory");

        state.pipes.append(Pipe{ .position = rl.Vector2.init(
            @floor(width),
            @floor(height - (openingLength + openingDistanceGround)),
        ), .up = true }) catch @panic("cannot allocate memory");
    }
}

fn doGameLogic(state: *GameState) !void {
    var bird = &state.bird;

    state.speed = @min(
        @max(@as(f32, @floatFromInt(state.distance)) / 2000, state.speed),
        10,
    );

    state.distance = state.distance + @as(u32, @intFromFloat(state.speed));

    bird.speed = bird.speed.add(gravity);
    if (birdShouldJump()) bird.speed = bird.speed.add(jumpVec);
    bird.speed = bird.speed.clampValue(-maxSpeed, maxSpeed);

    const res = rl.Vector2.add(bird.position, bird.speed);

    if (res.y < -15) {
        bird.speed = bird.speed.subtract(jumpVec);
    }
    bird.position = res;

    attemptMakeNewPipe(state);

    // move all pipes back by current speed.
    for (state.pipes.items) |*pipe| {
        pipe.position.x -= state.speed;
    }

    const arena = state.getArena() catch @panic("Failed to get Allocator");

    var pipes = makePipeCollisions(&state.pipes.items, arena);
    state.currentPipeCollisions = pipes;

    if (state.bird.position.y > @as(f32, @floatFromInt(state.screenHeight))) {
        bird.isDead = true;
    } else if (pipes) |*p| {
        const birdCollision = bird.getCollisionBox();

        for (p.*) |pipe| {
            bird.isDead = rl.checkCollisionRecs(pipe, birdCollision) or bird.isDead;
        }
    }
}

fn PaintScreen(state: *GameState) !void {
    const arenaAlloc: std.mem.Allocator = (try state.getArena()).*;

    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.white);

    const birdCollision = state.bird.getCollisionBox();

    if (state.pipes.items.len > 0) {
        const pipeCollisions =
            if (state.currentPipeCollisions) |col| col else @panic("Pipe collisions have not been made.");

        for (state.pipes.items, 0..) |_, idx| {
            rl.drawRectangleRec(
                pipeCollisions[idx],
                rl.Color.red,
            );
        }
    }

    rl.drawRectangleRec(birdCollision, if (state.bird.isDead) rl.Color.orange else rl.Color.black);

    const str: [:0]u8 = @ptrCast(try std.fmt.allocPrint(arenaAlloc, "Distance: {d:.3} \nSpeed: {d:.3} \nScore: {}", .{ state.distance, state.speed, state.score }));

    rl.drawText(str, 16, 16, 16, .black);
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
