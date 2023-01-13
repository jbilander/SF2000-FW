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

#include "flash.h"

extern void *flashbase;

/** flash_writeWord
 *
 * @brief Write a word to the Flash
 * @param address Address to write to
 * @param data The word to write
*/
void flash_writeWord(ULONG address, UWORD data) {
  address &= (FLASH_SIZE-1);
  flash_unlock_sdp();
  flash_command(CMD_WORD_PROGRAM);
  *(UWORD *)(flashbase + address) = data;
  flash_poll(address);

  return;
}

/** flash_command
 *
 * @brief send a command to the Flash
 * @param command
*/
void flash_command(UWORD command) {
  *(UWORD *)(flashbase + ADDR_CMD_STEP_1) = command;

  return;
}

/** flash_unlock_sdp
 *
 * @brief Send the SDP command sequence
*/
void flash_unlock_sdp() {
  *(UWORD *)(flashbase + ADDR_CMD_STEP_1) = CMD_SDP_STEP_1;
  *(UWORD *)(flashbase + ADDR_CMD_STEP_2) = CMD_SDP_STEP_2;

  return;
}

/** flash_erase_chip
 *
 * @brief Perform a chip erase
*/
void flash_erase_chip() {
  flash_unlock_sdp();
  flash_command(CMD_ERASE);
  flash_unlock_sdp();
  flash_command(CMD_ERASE_CHIP);

  flash_poll(0);
}

/** flash_erase_sector
 *
 * @brief Erase the specified sector
 * @param sector
*/
void flash_erase_sector(UBYTE sector) {
  flash_unlock_sdp();
  flash_command(CMD_ERASE);
  flash_unlock_sdp();
  ULONG address = (sector * SECTOR_SIZE);
  *(UWORD *)(flashbase + address) = CMD_ERASE_SECTOR;

  flash_poll(address);
}

/** flash_poll
 *
 * @brief Poll the status bits at address, until they indicate that the operation has completed.
 * @param address Address to poll
*/
void flash_poll(ULONG address) {
  address &= (FLASH_SIZE-1);
  volatile UWORD read1 = *(UWORD*)((void *)flashbase + address);
  volatile UWORD read2 = *(UWORD*)((void *)flashbase + address);
  while (((read1 & 1<<6) != (read2 & 1<<6))) {
    read1 = *(UWORD*)((void *)flashbase + address);
    read2 = *(UWORD*)((void *)flashbase + address);
  }
}

/** flash_identify
 *
 * @brief Check the manufacturer id of the device, return manuf and dev id
 * @param manuf Pointer to a UWORD that will be updated with the returned manufacturer id
 * @param devid Pointer to a UWORD that will be updatet with the returned device id
 * @return True if the manufacturer ID matches the expected value
*/
bool flash_identify(UWORD *manuf, UWORD *devid) {
  bool ret = false;

  flash_unlock_sdp();
  flash_command(CMD_ID_ENTRY);

  if (manuf) {
    *manuf = *(UWORD *)flashbase;
    ret = (*manuf == FLASH_MANUF);
  } else {
    ret = (*(UWORD *)flashbase == FLASH_MANUF);
  }

  if (devid) *devid = *(UWORD *)(flashbase + 2);

  flash_command(CMD_CFI_ID_EXIT);

  return (ret);
}
