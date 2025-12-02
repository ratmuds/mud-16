# mud-16
a little retro console with a Motorola 68000 and FPGA PPU

## Memory Map

| Address Range         | Size   | Region              | Description                          |
|-----------------------|--------|---------------------|--------------------------------------|
| `0x00000` - `0x1FFFF` | 128 KB | **ROM (Code)**      | Game code and program data           |
| `0x20000` - `0x9FFFF` | 512 KB | **ROM (Assets)**    | Sprites, tilesets, music, sound      |
| `0xA0000` - `0xBFFFF` | 128 KB | **VRAM**            | Video RAM for PPU                    |
| `0xC0000` - `0xDFFFF` | 128 KB | **WRAM**            | Work RAM for game state              |
| `0xE0000` - `0xFFFFF` | 128 KB | **Hardware Regs**   | Memory-mapped I/O and registers      |

**Total: 1 MB**
