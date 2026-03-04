pub const wood_beam = @import("modules/wood_beam.zig");
pub const beam_math = @import("engine/math.zig");
pub const loads = @import("engine/loads.zig");
pub const wood = @import("engine/materials/wood.zig");
pub const nds2018 = @import("engine/codes/nds2018.zig");

test {
    _ = wood_beam;
    _ = beam_math;
    _ = loads;
    _ = wood;
    _ = nds2018;
}
