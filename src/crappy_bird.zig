const std = @import("std");
const rl = @import("raylib");
const sq = @import("./scrolling_queue.zig");

const Ingame = @import("./ingame.zig");

pub const entityCap = 200;

pub const Pipe = struct {
    position: rl.Vector2,
    up: bool = false,
};

pub const Bird = struct {
    position: rl.Vector2,
    speed: rl.Vector2,
    isDead: bool = false,

    pub fn getCollisionBox(self: Bird) rl.Rectangle {
        return rl.Rectangle.init(self.position.x, self.position.y, 40, 40);
    }
};

var touchLast = false;

pub fn birdShouldJump() bool {
    const touch = rl.getTouchPointCount() > 0;
    defer touchLast = touch;

    return rl.isMouseButtonPressed(rl.MouseButton.left) or
        rl.isMouseButtonPressed(rl.MouseButton.right) or
        rl.isKeyPressed(rl.KeyboardKey.space) or
        touch != touchLast;
}

pub const GameScreen = enum {
    GAME,
    GAMEOVER,
    MENU,
};

pub const Assets = struct {
    pub const pipeBHeadUV = rl.Rectangle.init(0, 0, 48, 16);
    pub const pipeBodyUV = rl.Rectangle.init(0, 32, 48, 16);

    miku: rl.Texture2D,
    pipes: rl.Texture2D,
    coin: rl.Texture2D,
    gui: rl.Texture2D,

    pub fn init() !Assets {
        const mikuImg = try rl.loadImageFromMemory(".png", @embedFile("assets/miku.png"));
        defer mikuImg.unload();

        const pipes = try rl.loadImageFromMemory(".png", @embedFile("assets/pipes.png"));
        defer pipes.unload();

        const gui = try rl.loadImageFromMemory(".png", @embedFile("assets/gui.png"));
        defer gui.unload();

        const coin = try rl.loadImageFromMemory(".jpg", @embedFile("assets/coin.png"));
        defer coin.unload();

        return .{
            .miku = try rl.loadTextureFromImage(mikuImg),
            .pipes = try rl.loadTextureFromImage(pipes),
            .gui = try rl.loadTextureFromImage(gui),
            .coin = try rl.loadTextureFromImage(coin),
        };
    }

    pub fn deinit(self: *Assets) void {
        rl.unloadTexture(self.miku);
    }
};

pub const GameState = struct {
    rand: std.Random,
    allocator: std.mem.Allocator,
    arenaAlloc: ?*const std.mem.Allocator = null,

    screen: GameScreen,

    screenHeight: u32 = 0,
    screenWidth: u32 = 0,

    maxSpeed: f32 = 8,
    jumpVec: rl.Vector2 = rl.Vector2.init(0, -3),
    gravity: rl.Vector2 = rl.Vector2.init(0, 0.1),

    distance: u32 = 0,
    speed: f32 = 1,
    score: u32,
    bird: Bird,

    coins: *sq.FixedSizeScrollingQueue(rl.Vector2, entityCap),
    pipes: *sq.FixedSizeScrollingQueue(Pipe, entityCap),
    currentPipeCollisions: ?[]rl.Rectangle = null,
    lastPipeDistance: u32 = 0,

    pub fn getArena(self: GameState) error{OutOfMemory}!*const std.mem.Allocator {
        if (self.arenaAlloc) |_arenaAlloc| return _arenaAlloc else return error.OutOfMemory;
    }

    fn init(allocator: std.mem.Allocator, rand: std.Random, pipes: *sq.FixedSizeScrollingQueue(Pipe, entityCap), coins: *sq.FixedSizeScrollingQueue(rl.Vector2, entityCap)) GameState {
        return .{
            .allocator = allocator,
            .rand = rand,

            .screen = GameScreen.GAME,

            .score = 0,
            .distance = 0,
            .coins = coins,
            .pipes = pipes,
            
            .bird = .{ .speed = rl.Vector2{ .x = 0, .y = 0 }, .position = rl.Vector2.init(64, 450 / 2) },
        };
    }

    fn restart(self: GameState) GameState {
        self.pipes.empty();
        self.coins.empty();

        return GameState.init(self.allocator, self.rand, self.pipes, self.coins);
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const screenWidth = 800;
    const screenHeight = 450;
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(screenWidth, screenHeight, "Crappy Bird");
    rl.setTargetFPS(60);

    defer rl.closeWindow();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const rand = prng.random();

    var pipes = sq.FixedSizeScrollingQueue(Pipe, entityCap).init();
    var coins = sq.FixedSizeScrollingQueue(rl.Vector2, entityCap).init();
    var assets = try Assets.init();
    var state = GameState.init(allocator, rand, &pipes, &coins);

    while (!rl.windowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);

        state.screenHeight = @intCast(rl.getScreenHeight());
        state.screenWidth = @intCast(rl.getScreenWidth());
        state.arenaAlloc = &arena.allocator();

        state.maxSpeed = @as(f32, @floatFromInt(state.screenHeight / 60));
        state.jumpVec = rl.Vector2.init(0, -(state.maxSpeed * 0.60));
        state.gravity = rl.Vector2.init(0, state.maxSpeed / 40);

        std.debug.print("S: {} \n", .{pipes.getSize()});

        try Ingame.doGameLogic(&state);

        std.debug.print("SS: {} \n", .{pipes.getSize()});

        try Ingame.PaintScreen(&state, &assets);

        if (state.bird.isDead) {
            state = state.restart();
        }

        arena.deinit();
        state.currentPipeCollisions = null;
    }

    assets.deinit();
}
