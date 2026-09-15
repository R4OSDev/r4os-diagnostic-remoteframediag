const r4os = @import("r4os");
const std = @import("std");

const chunk_pixels = 64;

pub fn r4_app_main(r4_app: *r4os.App) i32 {
    var sys = r4_app.system();
    var desk = r4_app.desktop() orelse {
        sys.println("RFDIAG R4DESK unavailable");
        return 2;
    };

    sys.println("RFDIAG");
    const demand_supported = desk.supportsRemoteFrameDemand();
    var frame_acquired = false;
    if (demand_supported) {
        const acquire_rc = desk.remoteFrameAcquire();
        if (acquire_rc <= 0) {
            sys.println("RFDIAG frame acquire failed");
            return 1;
        }
        frame_acquired = true;
    }
    defer {
        if (frame_acquired) _ = desk.remoteFrameRelease();
    }

    const leave_owned = std.ascii.indexOfIgnoreCase(std.mem.span(sys.argsRaw()), "/EXITOWNED") != null;
    if (leave_owned) frame_acquired = false;
    const ok = checkRemoteFrame(&sys, &desk, leave_owned);
    sys.write("RFDIAG result: ");
    sys.println(if (ok) "OK" else "FAILED");
    return if (ok) 0 else 1;
}

fn checkRemoteFrame(sys: *const r4os.r4sys.Context, desk: *const r4os.r4desk.Context, leave_owned: bool) bool {
    var info: r4os.abi.RemoteFrameInfo = .{};
    var lease: r4os.abi.RemoteFrameLease = .{};
    var info_rc = desk.remoteFrameSnapshotAcquire(0, &info, &lease);
    var attempt: u32 = 0;
    while (info_rc != 0 and attempt < 200) : (attempt += 1) {
        sys.sleepTicks(1);
        info_rc = desk.remoteFrameSnapshotAcquire(0, &info, &lease);
    }
    if (info_rc != 0) return fail(sys, "RFDIAG frame-info unavailable");
    defer if (!leave_owned) { _ = desk.remoteFrameSnapshotRelease(&lease); };
    if (lease.id == 0 or lease.pixels_addr == 0 or lease.capacity_pixels < info.frame_pixels) return fail(sys, "RFDIAG snapshot lease failed");
    if (info.magic != r4os.abi.remote_frame_magic or info.version != r4os.abi.remote_frame_version) return fail(sys, "RFDIAG frame-info identity failed");
    if ((info.flags & r4os.abi.remote_frame_flag_ready) == 0 or
        (info.flags & r4os.abi.remote_frame_flag_dirty_valid) == 0 or
        (info.flags & r4os.abi.remote_frame_flag_cursor_valid) == 0)
    {
        return fail(sys, "RFDIAG frame flags failed");
    }
    if (info.format != r4os.abi.remote_frame_format_xrgb32 or info.bytes_per_pixel != 4) return fail(sys, "RFDIAG frame format failed");
    const expected_pixels = @as(u64, info.width) * @as(u64, info.height);
    const expected_bytes = expected_pixels * 4;
    if (info.width == 0 or info.height == 0 or info.stride_pixels != info.width or expected_pixels == 0 or
        expected_pixels != @as(u64, info.frame_pixels) or expected_bytes != @as(u64, info.frame_bytes))
    {
        return fail(sys, "RFDIAG frame geometry failed");
    }
    if (info.dirty_w == 0 or info.dirty_h == 0 or info.dirty_x < 0 or info.dirty_y < 0) return fail(sys, "RFDIAG dirty rect failed");
    const dirty_right = @as(u64, @intCast(info.dirty_x)) + @as(u64, info.dirty_w);
    const dirty_bottom = @as(u64, @intCast(info.dirty_y)) + @as(u64, info.dirty_h);
    if (dirty_right > @as(u64, info.width) or dirty_bottom > @as(u64, info.height)) {
        return fail(sys, "RFDIAG dirty bounds failed");
    }

    var head: [chunk_pixels]u32 = .{0} ** chunk_pixels;
    const pixels: [*]const u32 = @ptrFromInt(lease.pixels_addr);
    const head_rc: i32 = @intCast(@min(chunk_pixels, info.frame_pixels));
    @memcpy(head[0..@intCast(head_rc)], pixels[0..@intCast(head_rc)]);

    const tail_offset = if (info.frame_pixels > chunk_pixels) info.frame_pixels - chunk_pixels else 0;
    var tail: [chunk_pixels]u32 = .{0} ** chunk_pixels;
    const tail_rc: i32 = @intCast(@min(chunk_pixels, info.frame_pixels - tail_offset));
    @memcpy(tail[0..@intCast(tail_rc)], pixels[tail_offset..][0..@intCast(tail_rc)]);
    // Multiple consumers of one immutable revision share storage. Releasing
    // one exact token leaves the other valid; a repeated release is stale.
    var peer_info: r4os.abi.RemoteFrameInfo = .{};
    var peer: r4os.abi.RemoteFrameLease = .{};
    if (desk.remoteFrameSnapshotAcquire(info.revision, &peer_info, &peer) == 0) {
        const same = peer.id != lease.id and peer.pixels_addr == lease.pixels_addr and peer.epoch == lease.epoch;
        if (desk.remoteFrameSnapshotRelease(&peer) != 0 or !same or desk.remoteFrameSnapshotRelease(&peer) >= 0)
            return fail(sys, "RFDIAG snapshot sharing failed");
    }

    var wait_info: r4os.abi.RemoteFrameInfo = .{};
    const wait_rc = desk.remoteFrameWait(info.revision, 1, &wait_info);
    if (wait_rc < 0) return fail(sys, "RFDIAG wait failed");

    const head_sum = checksum(head[0..@as(usize, @intCast(head_rc))]);
    const tail_sum = checksum(tail[0..@as(usize, @intCast(tail_rc))]);
    if (checksum(pixels[0..@intCast(head_rc)]) != head_sum or checksum(pixels[tail_offset..][0..@intCast(tail_rc)]) != tail_sum)
        return fail(sys, "RFDIAG leased pixels changed");
    var stats: r4os.abi.RemoteFrameCaptureStats = .{};
    if (desk.remoteFrameCaptureStats(&stats) != 0 or stats.leases == 0 or stats.leases > 64 or stats.snapshots > 3 or
        stats.live_bytes > 64 * 1024 * 1024 or stats.snapshot_bytes > 3 * 64 * 1024 * 1024) return fail(sys, "RFDIAG snapshot bounds failed");
    sys.write("RFDIAG capture: leases="); sys.printU64(stats.leases);
    sys.write(" publisher-bytes="); sys.printU64(stats.published_bytes);
    sys.write(" snapshot-copy-bytes="); sys.printU64(stats.snapshot_copy_bytes);
    sys.write(" max-reader-ns="); sys.printU64(stats.max_reader_ns); sys.println("");
    sys.write("RFDIAG snapshot: OK mode=");
    sys.printU64(@as(u64, info.width));
    sys.write("x");
    sys.printU64(@as(u64, info.height));
    sys.write(" rev=");
    sys.printU64(@as(u64, info.revision));
    sys.write(" dirty=");
    sys.printI32(info.dirty_x);
    sys.write(",");
    sys.printI32(info.dirty_y);
    sys.write(",");
    sys.printU64(@as(u64, info.dirty_w));
    sys.write(",");
    sys.printU64(@as(u64, info.dirty_h));
    sys.write(" chunks=");
    sys.printI32(head_rc);
    sys.write("+");
    sys.printI32(tail_rc);
    sys.write(" sums=");
    sys.printU64(@as(u64, head_sum));
    sys.write("/");
    sys.printU64(@as(u64, tail_sum));
    sys.write(" wait=");
    sys.printI32(wait_rc);
    sys.println("");
    return true;
}

fn checksum(pixels: []const u32) u32 {
    var out: u32 = 0;
    var i: usize = 0;
    while (i < pixels.len) : (i += 1) {
        out +%= pixels[i] ^ @as(u32, @intCast(i));
        out = (out << 5) | (out >> 27);
    }
    return out;
}

fn fail(sys: *const r4os.r4sys.Context, msg: []const u8) bool {
    sys.println(msg);
    return false;
}
