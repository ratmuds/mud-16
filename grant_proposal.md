# Mud-16 Hardware Grant Proposal

## Project Overview

Mud-16 is a retro-inspired 16-bit game console featuring a Motorola 68000 CPU and a custom FPGA-based Picture Processing Unit (PPU). The goal of this project is to create a fully functional and well-documented homebrew console that is accessible to hobbyists and students.

## Current Status

The console's memory map is defined, and the PPU is partially implemented in SystemVerilog. A simulation environment using Verilator and Raylib allows for testing and visualization of the PPU's output.

### Implemented Features:
*   Tile-based background rendering
*   Sprite rendering (up to 128 on-screen)
*   Palette memory
*   Bus arbitration between the CPU and PPU

### To-Do list for Grant:
*   [x] Background scrolling (horizontal and vertical)
*   [ ] CPU-writable registers for PPU control (scrolling, palettes, etc.)
*   [ ] More advanced rendering features (e.g., parallax scrolling, tilemap layers)
*   [ ] Audio processing unit (APU) design and implementation
*   [ ] Design and fabrication of a physical PCB for the console

## Grant Goals

We are seeking funding to acquire the necessary hardware for prototyping and development. This includes:

*   A more powerful FPGA development board to accommodate the growing PPU and future APU.
*   A custom PCB to house the Motorola 68000, RAM, ROM, and other components.
*   A logic analyzer for debugging the interactions between the CPU, PPU, and other hardware.

This funding will accelerate the development of Mud-16 and help us achieve our goal of creating a complete and open-source retro gaming console.
