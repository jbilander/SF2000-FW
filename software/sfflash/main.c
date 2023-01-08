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

#define MANUF_ID 2092
#define PROD_ID  6

char *ks_filename;
void *flashbase;

bool op_copy_rom      = false;
bool op_program_flash = false;
bool op_erase_flash   = false;
bool op_erase_bank    = false;
bool op_identify      = false;
bool op_verify        = true;

ULONG program_bank = FLASH_BANK_1;

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
  if (parseArgs(argc,argv)) {
    if ((ExpansionBase = (struct ExpansionBase *)OpenLibrary("expansion.library",0)) != NULL) {
      struct ConfigDev *cd = NULL;
      if (cd = (struct ConfigDev*)FindConfigDev(NULL,MANUF_ID,PROD_ID)) {

        UWORD manufacturerId, deviceId;
        if (op_identify) {
          flash_identify(&manufacturerId,&deviceId);
          printf("Manufacturer: %04X, Device: %04X\n",manufacturerId, deviceId);
        } 
        
        if (flash_identify(&manufacturerId,&deviceId)) {

          if (op_erase_flash) {
            erase_chip();
          } else if (op_erase_bank) {
            erase_bank(program_bank);
          } else if (op_copy_rom) {
            printf("Copying Kickstart ROM to bank %d\n",(program_bank == FLASH_BANK_0) ? 0 : 1);
            copyRomToFlash(program_bank);
          } else if (op_program_flash) {
            ULONG romSize = 0;
            printf("Flashing kick file %s\n",ks_filename);
            if ((romSize = getFileSize(ks_filename)) != 0) {
              if (romSize == ROM_256K || romSize == ROM_512K || romSize == ROM_1M) {
                if (romSize == ROM_1M) {
                  erase_chip();
                } else {
                  erase_bank(program_bank);
                }
                if (romSize == ROM_1M) {
                  // Force Bank 0 for 1M rom as it will fill both banks.
                  copyFileToFlash(ks_filename,FLASH_BANK_0,romSize);
                } else {
                  copyFileToFlash(ks_filename,program_bank,romSize);
                }

              } else {
                printf("Bad rom size, 256K/512K/1M ROM required.\n");
                rc = 5;
              }
            }
          } else {
            usage();
          }

        } else {
          printf("Error: Chip ID failed, expected Manufacturer ID %04X but got %04X\n",FLASH_MANUF,manufacturerId);
          printf("Make sure ROM Override is disabled and try again\n");
          rc = 5;
        }

      } else {
        printf("Couldn't find board with Manufacturer/Prod ID of %d:%d\n",MANUF_ID,PROD_ID);
        rc = 5;
      }

    } else {
      printf("Couldn't open Expansion.library.\n");
      rc = 5;
    }

  }

  cleanup();
  return (rc);
}

void erase_bank(ULONG bank) {
  UBYTE sector = 0;
  int progress = 0;
  printf("Erasing bank %d\n", (program_bank == FLASH_BANK_0) ? 0 : 1);
  for (ULONG i = bank; i<bank + ROM_512K; i+=SECTOR_SIZE) {

    sector = i >> 12;
    progress = ((sector%128)*100)/128;

    if ((progress % 5) == 0) {
      fprintf(stdout,"\33[2K\rSector erase %d%%",progress);
      fflush(stdout);
    }

    flash_erase_sector(sector);
  }
  fprintf(stdout,"\33[2K\rSector erase 100%%\n");
}

void erase_chip() {
  printf("Erasing chip...");
  flash_erase_chip();
  printf(" Done\n");
}

int parseArgs(int argc, char *argv[]) {
  for (int i=1; i<argc; i++) {
    if (argv[i][0] == '-') {
      switch(argv[i][1]) {
        case 'c':
          op_copy_rom = true;
          break;
        case 'V':
          op_verify = false;
          break;
        case 'E':
          op_erase_flash = true;
          break;
        case 'e':
          op_erase_bank = true;
          break;
        case 'F':
        case 'f':
          if (i+1 < argc) {
            op_program_flash = true;
            ks_filename = argv[i+1];
            i++;
          }
          break;
        case 'i':
        case 'I':
          op_identify = true;
          break;
        case '1':
          program_bank = FLASH_BANK_1;
          break;
        case '0':
          program_bank = FLASH_BANK_0;
          break;
      }
    }
  }
  if (op_program_flash) {
    op_erase_flash = false;
    op_erase_bank  = false;
  }
  return 1;
}

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

void copyFileToFlash(char *filename, ULONG destination, ULONG romSize) {
  BPTR fh = Open(filename,MODE_OLDFILE);

  bool success = 0;

  if (fh) {
 
    APTR buffer = AllocMem(romSize, 0);
 
    if (buffer) {
      Read(fh,buffer,romSize);
      copyBufToFlash(buffer,destination,romSize);
      FreeMem(buffer,romSize);

    } else {
      printf("Unable to allocate memory.\n");
    }
  }
  if (fh) Close(fh);
  return;
}

void copyRomToFlash(ULONG destination) {
  ULONG *source = (void *)0xF80000;
  copyBufToFlash(source,destination,ROM_512K);
}

void copyBufToFlash(ULONG *source, ULONG destination, ULONG romSize) {
  int progress = 0;
  int lastProgress = 1;

  printf("Writing flash...\n");

  for (ULONG i=0; i<romSize; i+=2) {
    progress = (i+1)*100/romSize;

    if ((progress % 5) == 0 && lastProgress != progress) {
        fprintf(stdout,"\33[2K\rProgress: %3d%%",progress);
        fflush(stdout);
        lastProgress = progress;
    }

    flash_writeWord(destination+i,*(UWORD *)((void *)source+i));

    if (romSize == ROM_256K) {
      flash_writeWord(destination+i+ROM_256K,*(UWORD *)((void *)source+i));
    }

  }
  fprintf(stdout,"\33[2k\rProgress: 100%%\n");

  if (op_verify) {
    printf("Verifying...\n");

    UWORD flash_data  = 0;
    UWORD source_data = 0;
    ULONG flash_address = 0;

    for (ULONG i=0; i<romSize; i+=2) {

      progress = (i+1)*100/romSize;

      if ((progress % 5) == 0 && lastProgress != progress) {
          fprintf(stdout,"\33[2K\rProgress: %3d%%",progress);
          fflush(stdout);
          lastProgress = progress;
      }

      flash_address = (ULONG)flashbase + destination + i;        
      flash_data    = *(UWORD *)(void *)flash_address;
      source_data   = *(UWORD *)((void *)source+i);

      if (flash_data != source_data) {
        fprintf(stdout,"\nVerification failed at %06x - Expected %04X but read %04X\n",(int)flash_address,source_data,flash_data);
      }

    }

    fprintf(stdout,"\33[2k\rProgress: 100%%\n");
  }
}

void cleanup() {
  if (ExpansionBase != 0) CloseLibrary((struct Library *)ExpansionBase);
  if (DosBase != 0)       CloseLibrary((struct Library *)DosBase);
}

void usage() {
    printf("\nUsage: sfflash [-cfieEV] [-f <kickstart rom>] [-0|1] \n\n");
    printf("       -c                  -  Copy ROM to Flash.\n");
    printf("       -f <kickstart file> -  Write Kickstart to Flash.\n");
    printf("       -i                  -  Print Flash device id.\n");
    printf("       -e                  -  Erase bank.\n");
    printf("       -E                  -  Erase chip.\n");
    printf("       -V                  -  Skip verification.\n");
    printf("       -0                  -  Select bank 0 - $E0 ROM.\n");
    printf("       -1                  -  Select bank 1 - $F8 ROM (default, boot bank).\n");
}