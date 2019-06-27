Zig on Cortex-M33
=================

This repository includes a small example application that runs on [AN505], a Cortex-M33-based prototyping system on FPGA. Written entirely in [Zig].

[Zig]: https://ziglang.org
[AN505]: http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.dai0505b/index.html

## Usage

You need the following things before running this example:

- Either of the following:
    - [QEMU] 4.0.0 or later. Older versions are not tested but might work.
    - Arm [MPS2+] FPGA prototyping board configured with AN505. The encrypted FPGA image of AN505 is available from [Arm's website].
- Zig (TODO: minimum version?)

[QEMU]: https://www.qemu.org
[MPS2+]: https://www.arm.com/products/development-tools/development-boards/mps2-plus
[Arm's website]: https://developer.arm.com/tools-and-software/development-boards/fpga-prototyping-boards/download-fpga-images?_ga=2.138343728.123477322.1561466661-1332644519.1559889185

Do the following:

```shell
$ zig build -Drelease-small qemu
(Hit ^A X to quit QEMU)
The Secure code is running!
Booting the Non-Secure code...
NS: Hello from the Non-Secure world!
\
```

## License

This project is dual-licensed under the Apache License Version 2.0 and the MIT License.
