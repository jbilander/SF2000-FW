PROJECT=sfflash
CC=m68k-amigaos-gcc
CFLAGS=-lamiga -mcrt=nix13 -mcpu=68000
.PHONY:	clean all
all:	$(PROJECT)

OBJ = flash.o \
      main.o

SRCS = $(OBJ:%.o=%.c)

sfflash: $(SRCS)	*.h
	${CC} -o $@ $(CFLAGS) $(SRCS)

clean:
	-rm $(PROJECT)
