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

#include <exec/execbase.h>
#include <proto/exec.h>
#include <proto/expansion.h>
#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include <proto/dos.h>
#include <dos/dos.h>

#include "flash.h"
#include "main.h"
#include "config.h"

#define MANUF_ID 5194
#define PROD_ID  10

void *flashbase;

struct Library *DosBase;
struct ExecBase *SysBase;
struct ExpansionBase *ExpansionBase = NULL;

int main(int argc, char *argv[])
{
  SysBase = *((struct ExecBase **)4UL);
  DosBase = OpenLibrary("dos.library",0);

  int rc = 0;

  // TODO: Perhaps this should be found from autoconfig or something...
  flashbase = (void *)FLASHBASE;

  if (DosBase == NULL) {
    return(rc);
  }

  printf("Spitfire 2000 FlashROM tool\n");

  struct Config *config;
  if ((config = configure(argc,argv)) != NULL) {
    if ((ExpansionBase = (struct ExpansionBase *)OpenLibrary("expansion.library",0)) != NULL) {

      struct ConfigDev *cd = NULL;

      if (cd = (struct ConfigDev*)FindConfigDev(NULL,MANUF_ID,PROD_ID)) {

        UWORD manufacturerId, deviceId;

        bool check_device = flash_identify(&manufacturerId,&deviceId);

        if (check_device == false && config->op != OP_IDENTIFY) {

          printf("Error: Expected to see manufacturer id %04X but got %04X instead\n",FLASH_MANUF,manufacturerId);
          printf("Check that ROM overlay is switched off and try again.\n");

        } else {

          switch (config->op) {

            case OP_IDENTIFY:
              printf("Manufacturer: %04X, Device: %04X\n",manufacturerId, deviceId);
            break;

            case OP_VERIFY:
              if (config->source == SOURCE_ROM) {
                rc = (verifyBank((ULONG *)0xF80000,config->programBank,ROM_512K)) ? 0 : 5;
              } else {
                rc = (verifyFile(config->ks_filename,config->programBank)) ? 0 : 5;
              }
              break;

            case OP_ERASE_BANK:
              erase_bank(config->programBank);
              break;

            case OP_ERASE_CHIP:
              erase_chip();
              break;

            case OP_PROGRAM:
              if (config->source == SOURCE_ROM) {
                erase_bank(config->programBank);
                printf("Copying Kickstart ROM to bank %d\n",(config->programBank == FLASH_BANK_0) ? 0 : 1);
                copyBufToFlash((void *)0xF80000,config->programBank,ROM_512K,config->skipVerify);
              } else {
                ULONG romSize = 0;
                printf("Flashing kick file %s\n",config->ks_filename);
                if ((romSize = getFileSize(config->ks_filename)) != 0) {
                  if (romSize == ROM_256K || romSize == ROM_512K || romSize == ROM_1M) {
                    if (romSize == ROM_1M) {
                      erase_chip();
                    } else {
                      erase_bank(config->programBank);
                    }
                    if (romSize == ROM_1M) {
                      // Force Bank 0 for 1M rom as it will fill both banks.
                      copyFileToFlash(config->ks_filename,FLASH_BANK_0,romSize,config->skipVerify);
                    } else {
                      copyFileToFlash(config->ks_filename,config->programBank,romSize,config->skipVerify);
                    }
                  } else {
                    printf("Bad file size, 256K/512K/1M ROM required.\n");
                    rc = 5;
                  }
                }
              }
              break;

              case OP_NONE:
                usage();
                break;
          }
        }

      } else {
        printf("Couldn't find board with Manufacturer/Prod ID of %d:%d\n",MANUF_ID,PROD_ID);
        rc = 5;
      }

    } else {
      printf("Couldn't open Expansion.library.\n");
      rc = 5;
    }

  } else {
    usage();
  }

  if (config)        FreeMem(config,sizeof(struct Config));
  if (ExpansionBase) CloseLibrary((struct Library *)ExpansionBase);
  if (DosBase)       CloseLibrary((struct Library *)DosBase);

  return (rc);
}

/**
 * erase_bank
 *
 * @brief Erase a bank
 * @param bank Address of the bank to erase
*/
void erase_bank(ULONG bank) {
  bank &= ~((ULONG)BANK_SIZE-1);
  UBYTE sector = 0;
  int progress = 0;

  fprintf(stdout,"Erasing bank %d:     ", (bank == FLASH_BANK_0) ? 0 : 1);
  fflush(stdout);
  for (ULONG i = bank; i<bank + ROM_512K; i+=SECTOR_SIZE) {

    sector = i / SECTOR_SIZE;
    progress = ((sector%BANK_SECTORS)*100)/(BANK_SECTORS-1);

    fprintf(stdout,"\b\b\b\b%3d%%",progress);
    fflush(stdout);

    flash_erase_sector(sector);
  }
  printf("\n");
}

/**
 * erase_chip
 *
 * @brief Completely erase the flash
*/
void erase_chip() {
  printf("Erasing chip...");
  flash_erase_chip();
  printf(" Done\n");
}

/**
 * getFileSize
 *
 * @brief return the size of a file in bytes
 * @param filename file to check the size of
 * @returns File size in bytes
*/
ULONG getFileSize(char *filename) {
  BPTR fileLock;
  ULONG fileSize = 0;
  struct FileInfoBlock *FIB;

  FIB = (struct FileInfoBlock *)AllocMem(sizeof(struct FileInfoBlock),MEMF_CLEAR);

  if ((fileLock = Lock(filename,ACCESS_READ)) != 0) {

    if (Examine(fileLock,FIB)) {
      fileSize = FIB->fib_Size;
    }

  } else {
    printf("Error opening %s\n",filename);
  }

  if (fileLock) UnLock(fileLock);
  if (FIB) FreeMem(FIB,sizeof(struct FileInfoBlock));

  return (fileSize);
}

/**
 * readFileToBuF
 *
 * @brief Read the rom file to a buffer
 * @param filename Name of the file to open
 * @return Pointer to a buffer
*/
APTR readFileToBuf(char *filename) {
  ULONG romSize = getFileSize(filename);
  if (romSize == 0) return NULL;

  BPTR fh;
  APTR buffer;

  buffer = AllocMem(romSize,MEMF_ANY);
  if (buffer) {
    fh = Open(filename,MODE_OLDFILE);

    if (fh) {
      Read(fh,buffer,romSize);
      Close(fh);
    } else {
      printf("Error opening %s\n",filename);
      return NULL;
    }

  } else {
    printf("Couldn't allocate memory.\n");
    return NULL;
  }

  return buffer;
}

/**
 * copyFileToFlash
 *
 * @brief Copy the contents of the specified file to the flash
 * @param filename A pointer to the source buffer
 * @param destination Bank address to write to
 * @param romSize Size in bytes of the source
 * @param skipVerify Skip verification
*/
void copyFileToFlash(char *filename, ULONG destination, ULONG romSize, bool skipVerify) {
  APTR buffer;

  if ((buffer = readFileToBuf(filename)) != NULL) {
    copyBufToFlash(buffer,destination,romSize,skipVerify);
    FreeMem(buffer,romSize);
  }

  return;
}

/**
 * copyBufToFlash
 *
 * @brief Copy the contents of the buffer to the flash
 * @param source A pointer to the source buffer
 * @param destination Bank address to write to
 * @param romSize Size in bytes of the source
 * @param skipVerify Skip verification
*/
void copyBufToFlash(ULONG *source, ULONG destination, ULONG romSize, bool skipVerify) {
  int progress = 0;
  int lastProgress = 1;

  UWORD *sourcePtr = NULL;

  ULONG byteCount = (romSize == ROM_256K) ? ROM_512K : romSize; // For 256K ROMs fill up a 512K bank

  fprintf(stdout,"Writing:     ");
  fflush(stdout);
  for (ULONG i=0; i<byteCount; i+=2) {
    sourcePtr = ((void *)source + (i % romSize)); // Loop the source address around when programming 256K
    progress = i*100/(byteCount-2);

    if (lastProgress != progress) {
        fprintf(stdout,"\b\b\b\b%3d%%",progress);
        fflush(stdout);
        lastProgress = progress;
    }

    flash_writeWord(destination+i,*sourcePtr);

  }
  printf("\n");
  if (skipVerify == false) {
    verifyBank(source,destination,romSize);
  }
}

/** verifyBank
 *
 * @brief compare the specified bank with a buffer
 * @returns success
 * @param source A pointer to the source buffer
 * @param bank The bank address to compare
*/
bool verifyBank(ULONG *source, ULONG bank, ULONG romSize) {
  fprintf(stdout,"Verifying:     ");
  fflush(stdout);

  ULONG progress     = 0;
  ULONG lastProgress = 1;

  UWORD flash_data    = 0;
  ULONG flash_address = 0;
  UWORD source_data   = 0;

  ULONG byteCount = (romSize == ROM_256K) ? ROM_512K : romSize; // For 256K ROMs fill up a 512K bank

  for (ULONG i=0; i<byteCount; i+=2) {

    progress = i*100/(byteCount-2);

    if (lastProgress != progress) {
        fprintf(stdout,"\b\b\b\b%3d%%",(int)progress);
        fflush(stdout);
        lastProgress = progress;
    }

    flash_address = (ULONG)flashbase + bank + i;
    flash_data    = *(UWORD *)(void *)flash_address;
    source_data   = *(UWORD *)((void *)source + (i % romSize)); // Loop the source address around when programming 256K

    if (flash_data != source_data) {
      printf("\nVerification failed at %06x - Expected %04X but read %04X\n",(int)flash_address,source_data,flash_data);
      return false;
    }

  }
  printf("\n");
  return true;
}

/**
 * verifyFile
 *
 * @brief Compare the specified bank with a file
 * @returns success
 * @param filename Filename
 * @param bank Bank address to compare
*/
bool verifyFile(char *filename, ULONG bank) {
  ULONG romSize;
  APTR buffer;

  bool success = false;

  if ((romSize = getFileSize(filename)) != 0) {
    if (romSize == ROM_256K || romSize == ROM_512K || romSize == ROM_1M) {
        if ((buffer = readFileToBuf(filename)) != NULL) {
          if (romSize == ROM_1M) bank = FLASH_BANK_0;
          success = verifyBank(buffer,bank,romSize);
          FreeMem(buffer,romSize);
      }
    } else {
      printf("Bad file size, 256K/512K/1M ROM required.\n");
      return false;
    }
  } else {
    return false;
  }
  return success;
}
