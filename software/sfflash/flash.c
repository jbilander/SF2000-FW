#include "flash.h"
#include <unistd.h>

extern void *flashbase;
extern struct Library *DosBase;

void flash_writeWord(ULONG address, UWORD data) {
  address &= 0xFFFFF;
  flash_unlock_sdp();
  flash_command(CMD_WORD_PROGRAM);
  *(UWORD *)(flashbase + address) = data;
  //flash_wait();
  flash_poll(address);
  return;
}

void flash_command(UWORD command) {
  *(UWORD *)(flashbase + ADDR_CMD_STEP_1) = command;
  return;
}

void flash_unlock_sdp() {
  *(UWORD *)(flashbase + ADDR_CMD_STEP_1) = CMD_SDP_STEP_1;
  *(UWORD *)(flashbase + ADDR_CMD_STEP_2) = CMD_SDP_STEP_2;
  return;
}

void flash_erase_chip() {
  flash_unlock_sdp();
  flash_command(CMD_ERASE);
  flash_unlock_sdp();
  flash_command(CMD_ERASE_CHIP);
  //flash_wait();
  flash_poll(0);
}

void flash_erase_sector(UBYTE sector) {
  flash_unlock_sdp();
  flash_command(CMD_ERASE);
  flash_unlock_sdp();
  ULONG address = sector << 12;
  *(UWORD *)(flashbase + address) = CMD_ERASE_SECTOR;
  //flash_wait();
  flash_poll(address);
}

void flash_wait() {
  // Poll RDY status
  volatile UWORD *status = (void *)FLASH_CONTROL;
  while ((*status & FLASH_BUSY) != 0) {
    ;;
  }
  return;
}

void flash_poll(ULONG address) {
  volatile UWORD read1 = *(UWORD*)((void *)flashbase + address);
  volatile UWORD read2 = *(UWORD*)((void *)flashbase + address);
  while (((read1 & 1<<6) != (read2 & 1<<6))) {
    read1 = *(UWORD*)((void *)flashbase + address);
    read2 = *(UWORD*)((void *)flashbase + address);
  }
}

bool flash_identify(UWORD *manuf, UWORD *devid) {
  bool ret = false;
  flash_unlock_sdp();
  flash_command(CMD_ID_ENTRY);
  if (manuf) {
    *manuf  = *(UWORD *)flashbase;
    ret = (*manuf == FLASH_MANUF);
  } else {
    ret = (*(UWORD *)flashbase == FLASH_MANUF);
  }
  if (devid) *devid  = *(UWORD *)(flashbase + 2);
  flash_command(CMD_CFI_ID_EXIT);
  return (ret);
}