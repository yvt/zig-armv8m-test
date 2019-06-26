const CTRL_SECURITY_ERROR_RESPONSE: u32 = 1 << 4;
const CTRL_AUTOINCREMENT: u32 = 1 << 8;

/// The device driver for the TrustZone Memory Protection Controller.
///
/// It is documented in the ARM CoreLink SIE-200 System IP for Embedded TRM
/// (DDI 0571G):
/// <https://developer.arm.com/products/architecture/m-profile/docs/ddi0571/g>
/// A software implementation can be found in QEMU's `tz-mpc.c`.
pub const TzMpc = struct {
    base: usize,

    const Self = @This();

    /// Construct a `Pl011` object using the specified MMIO base address.
    pub fn withBase(base: usize) Self {
        return Self{ .base = base };
    }

    /// Assign an address range to Non-Secure.
    ///
    /// The range might be rounded to the block size the hardware is configured
    /// with.
    pub fn assignRangeToNonSecure(self: Self, start: u32, end: u32) void {
        self.update_range(start, end, Masks{ 0x00000000, 0xffffffff });
    }

    /// Assign an address range to Secure.
    ///
    /// The range might be rounded to the block size the hardware is configured
    /// with.
    pub fn assignRangeToSecure(self: Self, start: u32, end: u32) void {
        self.update_range(start, end, Masks{ 0x00000000, 0x00000000 });
    }

    pub fn setEnableBusError(self: Self, value: bool) void {
        if (value) {
            self.reg_ctrl().* |= CTRL_SECURITY_ERROR_RESPONSE;
        } else {
            self.reg_ctrl().* &= ~CTRL_SECURITY_ERROR_RESPONSE;
        }
    }

    fn regCtrl(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base);
    }

    fn regBlkMax(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x10);
    }

    fn regBlkCfg(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x14);
    }

    fn regBlkIdx(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x18);
    }

    fn regBlkLut(self: Self) *volatile u32 {
        return @intToPtr(*volatile u32, self.base + 0x1c);
    }

    // TODO: Registers related to interrupt

    fn blockSizeShift(self: Self) u5 {
        return @truncate(u5, self.reg_blk_cfg().*) + 5;
    }

    fn updateLut(self: Self, masks: Masks) void {
        const lut = self.reg_blk_lut();
        lut.* = (lut.* & masks[0]) ^ masks[1];
    }

    fn updateRange(self: Self, start: u32, end: u32, masks: Masks) void {
        // (Silently) round to the block size used by the hardware
        const shift = self.block_size_shift();
        start >>= shift;
        end >>= shift;

        if (start >= end) {
            return;
        }

        const start_group = start / 32;
        const end_group = end / 32;

        self.reg_ctrl().* &= ~CTRL_AUTOINCREMENT;
        self.reg_blk_idx().* = start_group;

        if (start_group == end_group) {
            masks = filter_masks(masks, ones_from(start % 32) ^ ones_from(end % 32));
            self.update_lut(masks);
        } else {
            var group = start_group;

            if ((start % 32) != 0) {
                const cap_masks = filter_masks(masks, ones_from(start % 32));
                self.update_lut(cap_masks);

                group += 1;
                self.reg_blk_idx().* = group;
            }

            while (group < end_group) {
                self.update_lut(masks);

                group += 1;
                self.reg_blk_idx().* = group;
            }

            if ((end % 32) != 0) {
                const cap_masks = filter_masks(masks, ~ones_from(end % 32));
                self.update_lut(cap_masks);
            }
        }
    }
};

/// AND and XOR masks.
const Masks = [2]u32;

fn filterMasks(masks: Masks, filter: u32) Masks {
    return Masks{ masks[0] & ~filter, masks[1] & filter };
}

/// Returns `0b11111000...000` where the number of trailing zeros is specified
/// by `pos`. `pos` must be in `[0, 31]`.
fn onesFrom(pos: u32) u32 {
    return u32(0xffffffff) << @intCast(u5, pos);
}
