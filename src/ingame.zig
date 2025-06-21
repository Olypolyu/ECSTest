const std = @import("std");
const rl = @import("raylib");
const CrappyBird = @import("./crappy_bird.zig");

const Pipe = CrappyBird.Pipe;
const GameState = CrappyBird.GameState;
const Assets = CrappyBird.Assets;

const pipeWidth = 80;
const pipeLipWitdh = 10;
const pipeLipHeight = 30;

fn makePipeCollisions(pipes: *[]Pipe, arena: *const std.mem.Allocator) ?[]rl.Rectangle {
    // creates a array containing the collisions for every pipe according to state.
    // Should be called every frame. The array is detroyed afterwards.

    if (pipes.len == 0) return null;

    var pipeCollisions =
        arena.alloc(rl.Rectangle, pipes.len) catch @panic("Couldn't allocate memory.");

    const height: f32 = @floatFromInt(rl.getScreenHeight());

    for (pipes.*, 0..) |pipe, idx| {
        if (pipe.up) {
            pipeCollisions[idx] =
                rl.Rectangle.init(
                    pipe.position.x,
                    0,
                    pipeWidth,
                    pipe.position.y,
                );
        } else {
            pipeCollisions[idx] =
                rl.Rectangle.init(
                    pipe.position.x,
                    pipe.position.y,
                    pipeWidth,
                    height - pipe.position.y,
                );
        }
    }

    return pipeCollisions;
}

fn attemptMakeNewPipe(state: *GameState) void {
    const width: f32 = @floatFromInt(rl.getScreenWidth());
    const height: f32 = @floatFromInt(rl.getScreenHeight());

    const amountBeforePipe = 300;

    if ((state.distance - state.lastPipeDistance) >= amountBeforePipe) {
        state.lastPipeDistance = state.distance;

        const openingLength = @max((height * 0.75) * state.rand.float(f32), height * 0.25);
        const openingDistanceGround = (height - openingLength) * state.rand.float(f32);

        state.pipes.add(Pipe{ .position = rl.Vector2.init(
            @floor(width),
            @floor(height - openingDistanceGround),
        ), .up = false }) catch @panic("cannot allocate memory");

        state.pipes.add(Pipe{ .position = rl.Vector2.init(
            @floor(width),
            @floor(height - (openingLength + openingDistanceGround)),
        ), .up = true }) catch @panic("cannot allocate memory");
    }
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

pub fn doGameLogic(state: *GameState) !void {
    var bird = &state.bird;

    state.speed = @min(
        @max(@as(f32, @floatFromInt(state.distance)) / 2000, state.speed),
        10,
    );

    state.distance = state.distance + @as(u32, @intFromFloat(state.speed));

    bird.speed = bird.speed.add(state.gravity);
    if (CrappyBird.birdShouldJump()) bird.speed = bird.speed.add(state.jumpVec);
    bird.speed = bird.speed.clampValue(-state.maxSpeed, state.maxSpeed);

    const res = rl.Vector2.add(bird.position, bird.speed);

    if (res.y < -15) {
        bird.speed = bird.speed.subtract(state.jumpVec);
    }
    bird.position = res;

    attemptMakeNewPipe(state);

    // move all pipes back by current speed.
    for (state.pipes.indices()) |pipeIdx| {
        state.pipes.data[pipeIdx].position.x -= state.speed;
    }

    if (state.pipes.first()) |firstPipe| {
        if (firstPipe.position.x < -(pipeLipWitdh + pipeWidth)) {
            _ = try state.pipes.pop();
        }
    }

    const arena = state.getArena() catch @panic("Failed to get Allocator");

    var pipeSlice = try state.pipes.toSlice(arena);
    var pipes = makePipeCollisions(&pipeSlice, arena);
    state.currentPipeCollisions = pipes;

    if (state.bird.position.y > @as(f32, @floatFromInt(state.screenHeight))) {
        bird.isDead = true;
    } else if (pipes) |*p| {
        const birdCollision = bird.getCollisionBox();
        for (p.*) |pipe| {
            bird.isDead = bird.isDead or rl.checkCollisionRecs(pipe, birdCollision);
        }
    }
}

pub fn PaintScreen(state: *GameState, assets: *Assets) !void {
    const arenaAlloc: std.mem.Allocator = (try state.getArena()).*;

    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.white);

    if (state.pipes.getSize() > 0) {
        const pipeCollisions =
            if (state.currentPipeCollisions) |col| col else @panic("Pipe collisions have not been made.");

        var indices: [CrappyBird.entityCap]u32 = undefined;

        const size = state.pipes.getSize();
        @memcpy(indices[0..size], state.pipes.indices());

        for (indices[0..size], 0..) |pipeIndex, colIndex| {
            const pipe = &state.pipes.data[pipeIndex];
            const rec = pipeCollisions[colIndex];

            assets.pipes.drawPro(
                Assets.pipeBodyUV,
                rec,
                rl.Vector2.init(0, 0),
                0,
                rl.Color.white,
            );

            if (pipe.up) {
                assets.pipes.drawPro(
                    Assets.pipeBHeadUV,
                    rl.Rectangle.init(rec.x - (pipeLipWitdh / 2), rec.y + rec.height - pipeLipHeight, rec.width + pipeLipWitdh, pipeLipHeight),
                    rl.Vector2.init(0, 0),
                    0,
                    rl.Color.white,
                );
            } else {
                assets.pipes.drawPro(
                    Assets.pipeBHeadUV,
                    rl.Rectangle.init(rec.x - (pipeLipWitdh / 2), rec.y, rec.width + pipeLipWitdh, pipeLipHeight),
                    rl.Vector2.init(0, 0),
                    0,
                    rl.Color.white,
                );
            }
        }
    }

    //const birdPos = state.bird.position;
    //rl.drawTexture(assets.miku, @intFromFloat(birdPos.x), @intFromFloat(birdPos.y), rl.Color.white);
    assets.miku.drawPro(
        rl.Rectangle.init(0, 0, @floatFromInt(assets.miku.width), @floatFromInt(assets.miku.height)),
        state.bird.getCollisionBox(),
        rl.Vector2.init(0, 0),
        0,
        rl.Color.white,
    );

    const str: [:0]u8 = @ptrCast(try std.fmt.allocPrint(arenaAlloc, "Distance: {d:.3} \nSpeed: {d:.3} \nScore: {}", .{ state.distance, state.speed, state.score }));
    rl.drawText(str, 16, 16, 16, .black);
}
