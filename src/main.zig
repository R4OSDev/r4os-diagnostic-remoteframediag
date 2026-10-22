//! Transitional entry; the single public oracle belongs to Spectra.
const r4os = @import("r4os");
const std = @import("std");
pub fn r4_app_main(app: *r4os.App) i32 {
    const sys = app.system();
    const desk = app.desktop() orelse return 2;
    const args = app.args();
    const leave_owned = std.ascii.eqlIgnoreCase(args, "/EXITOWNED");
    if (args.len != 0 and !leave_owned and !std.ascii.eqlIgnoreCase(args, "/DESKTOP")) return 2;
    const result = @import("spectra_remoteframe").run(&sys, &desk, leave_owned);
    sys.write("RFDIAG capture: leases=");
    sys.printU64(if (result.stats) |stats| stats.leases else 0);
    sys.write(" cleanup=");
    sys.println(if (result.held_until_exit) "held-until-real-exit" else if (result.cleanup_ok) "acknowledged" else "failed");
    if (result.exit_code == 0) sys.println("RFDIAG snapshot: OK (shared Spectra oracle)");
    sys.write("RFDIAG result: ");
    sys.println(if (result.exit_code == 0) "OK" else result.reason);
    return result.exit_code;
}
