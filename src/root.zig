pub const wood_beam = @import("modules/wood_beam.zig");
pub const wood_column = @import("modules/wood_column.zig");
pub const spread_footing = @import("modules/spread_footing.zig");
pub const beam_math = @import("engine/math.zig");
pub const loads = @import("engine/loads.zig");
pub const wood = @import("engine/materials/wood.zig");
pub const concrete = @import("engine/materials/concrete.zig");
pub const nds2018 = @import("engine/codes/nds2018.zig");
pub const aci318 = @import("engine/codes/aci318.zig");

test {
    _ = wood_beam;
    _ = wood_column;
    _ = spread_footing;
    _ = beam_math;
    _ = loads;
    _ = wood;
    _ = concrete;
    _ = nds2018;
    _ = aci318;
}
