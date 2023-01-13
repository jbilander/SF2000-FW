// SPDX-License-Identifier: GPL-2.0-only
/* This file is part of sfflash
 * Copyright (C) 2023 Matthew Harlum <matt@harlum.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 2.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

#include <exec/types.h>
#include <stdbool.h>


#define ROM_256K 0x040000
#define ROM_512K 0x080000
#define ROM_1M   0x100000


// SST 39LF802
#define FLASH_MANUF   0x00BF

#define SECTOR_SIZE  (2048 << 1)
#define BANK_SIZE    0x080000
#define BANK_SECTORS (BANK_SIZE / SECTOR_SIZE)
#define FLASH_SIZE   0x100000
//

#define FLASHBASE     0xA00000

#define FLASH_BANK_0  0x000000
#define FLASH_BANK_1  0x080000

// Command addresses left-shifted because Flash A0 = CPU A1
#define ADDR_CMD_STEP_1  (0x555 << 1)
#define ADDR_CMD_STEP_2  (0x2AA << 1)

#define CMD_SDP_STEP_1   0xAAAA
#define CMD_SDP_STEP_2   0x5555
#define CMD_WORD_PROGRAM 0xA0A0
#define CMD_ERASE        0x8080
#define CMD_ERASE_SECTOR 0x5050
#define CMD_ERASE_CHIP   0x1010
#define CMD_ID_ENTRY     0x9090
#define CMD_CFI_ENTRY    0x9898
#define CMD_CFI_ID_EXIT  0xF0F0

void flash_unlock_sdp();
void flash_erase_chip();
void flash_command(UWORD);
void flash_writeWord(ULONG, UWORD);
bool flash_identify(UWORD *, UWORD *);
void flash_wait();
void flash_erase_sector(UBYTE);
void flash_poll(ULONG);