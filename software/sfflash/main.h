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

ULONG getFileSize(char *);
void copyFileToFlash(char *, ULONG, ULONG, bool);
void copyRomToFlash(ULONG, bool);
void copyBufToFlash(ULONG *, ULONG, ULONG, bool);
void erase_bank(ULONG);
void erase_chip();
void usage();
bool verifyBank(ULONG *, ULONG, ULONG);
bool verifyFile(char *, ULONG);
APTR readFileToBuf(char *);