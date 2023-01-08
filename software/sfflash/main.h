int parseArgs(int, char* []);
void cleanup();
ULONG getFileSize(char *);
void copyFileToFlash(char *, ULONG, ULONG);
void copyRomToFlash(ULONG);
void copyBufToFlash(ULONG *, ULONG, ULONG);
void erase_bank(ULONG);
void erase_chip();
void usage();
