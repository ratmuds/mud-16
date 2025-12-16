# mud-16
a little retro console with a Motorola 68000 and FPGA PPU

# features
- 3.5" IPS Display
- D-pad and ABXY buttons
- 27 MHz FPGA
- Rechargable Battery
- 512 KB of SRAM

## why
I think that the GameBoy and other retro game console are really cool, and I want to make my own console. But I didn't want to just emulate it, I wanted to use a real retro CPU and make my own PPU (picture processing unit) with a FPGA.

## how
The CPU is the brain pretty much. It handles all the game logic and stuff. It's connected to 512 KB of SRAM which the first part of it is allocated to VRAM. The VRAM is used by the FPGA. The CPU needs to go through level shifters down to 3.3V, and the CPU and FPGA needs to handle bus arbitration properly, otherwise they will fight over the bus and everything will become a mess. The FPGA will request for the bus at the beginning of each frame where they will essentially perform a handshake and the bus will be passed to the FPGA. The FPGA then accesses all the VRAM it needs and then gives back control to the CPU.

The display will be running in 8 bit parallel mode, since SPI is too slow.

## to use
this stuff is WIP

you'll need to flash everything to the FPGA which will load all the necessary data into RAM for the CPU. The Gowin IDE is the app you'll use to flash the Tang Nano.

<img width="969" height="708" alt="image" src="https://github.com/user-attachments/assets/e5b9deb2-64ed-4b95-a4d6-570b346a1224" />

<img width="776" height="844" alt="image" src="https://github.com/user-attachments/assets/61a36859-6648-4163-92f0-3ed2e4d5f020" />
