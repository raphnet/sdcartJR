; SD-Cart JR : PCJR Card reader cartridge
; Copyright (C) 2020 Raphael Assenat <raph@raphnet.net>
;
; This program is free software; you can redistribute it and/or
; modify it under the terms of the GNU General Public License
; as published by the Free Software Foundation; either version 2
; of the License, or (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; File int13h.asm
;;;
;;; Interrupt 13h (Disk services) implementation.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

bits 16
cpu 8086

section .text

%undef TRACE_INT
%define INIT_RETRIES	255


; Disk status codes
%define STATUS_NO_ERROR					0x00
%define STATUS_BAD_COMMAND				0x01
%define STATUS_SECTOR_NOT_FOUND			0x04
%define STATUS_FIXED_DISK_RESET_FAILED	0x05
%define STATUS_FIXED_DISK_DRV_NOT_READY	0xAA

; Fixed disk geometry
%define GEO_CYLINDERS	142
%define GEO_SECTORS_PER_TRACK	63
%define GEO_HEADS				16

%include 'chs2lba.asm'

%define CMOS_DRIVE_TYPE	0


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_card_drive80: Card int13h handler for drive 80
	;
int13h_card_drive80:
	pushf
	cmp dl, 0x80
	jne _int13h_common.not_disk
	jmp _int13h_common


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_card_drive81: Card int13h handler for drive 81
	;
int13h_card_drive81:
	pushf
	cmp dl, 0x81
	jne _int13h_common.not_disk
	jmp _int13h_common


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_card_drive82: Card int13h handler for drive 82
	;
int13h_card_drive82:
	pushf
	cmp dl, 0x82
	jne _int13h_common.not_disk
	jmp _int13h_common


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_card_drive83: Card int13h handler for drive 83
	;
int13h_card_drive83:
	pushf
	cmp dl, 0x83
	jne _int13h_common.not_disk
	jmp _int13h_common


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; _int13h_common: Common int13h code past the initial drive ID check
	;
	; For use by the above entry points. Do not call directly.
	;
_int13h_common:
	sti
	cld
	push bp
	push ds

	; Restore our data segment
	mov bp, cs
	mov ds, bp

	; Range-check the function number.
	cmp ah, 0x1A
	jg int13_iret_stc	; Return with carry flag SET (error)

%ifdef TRACE_INT
	push dx
	mov dl, '['
	call putchar
	mov dl, ah
	call printHexByte
	mov dl, ']'
	call putchar
	pop dx
%endif

	; Arrange a jump to the correct routine
	mov bp, ax	; Backup AX
	xor al, al	; Clear AL
	xchg al, ah	; Mov AH (function no) to AL (AX now equals func. no)
	shl ax, 1	; Multiply by 2 (each ptr is a word)
	xchg ax, bp	; Restore AX, BP is now the function offset
	add bp, int13h_functions ; Add the base of the table

	jmp [cs:bp]	; Jump to it!

	; not reached

.not_disk:
	popf
	int NEWINT13
	retf 2

; Exit point with carry cleared.
int13_iret_clc:
%ifdef TRACE_INT
	push dx
	mov dl, 'c'
	call putchar
	pop dx
%endif
	pop ds
	pop bp
	popf
	clc
	retf 2

; Exit point with carry set.
int13_iret_stc:
%ifdef TRACE_INT
	push dx
	mov dl, 'C'
	call putchar
	pop dx
%endif
	pop ds
	pop bp
	popf
	stc
	retf 2

; Table of pointers for int13h functions
int13h_functions:
	dw int13h_fn00
	dw int13h_fn01
	dw int13h_fn02
	dw int13h_fn03
	dw int13h_fn04
	dw int13h_fn05
	dw int13h_fn06
	dw int13h_fn07
	dw int13h_fn08
	dw int13h_fn09
	dw int13h_fn0a
	dw int13h_fn0b
	dw int13h_fn0c
	dw int13h_fn0d
	dw int13h_fn0e
	dw int13h_fn0f
	dw int13h_fn10
	dw int13h_fn11
	dw int13h_fn12
	dw int13h_fn13
	dw int13h_fn14
	dw int13h_fn15
	dw int13h_fn16
	dw int13h_fn17
	dw int13h_fn18
	dw int13h_fn19
	dw int13h_fn1a


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn00 : Reset Disk System
	;
int13h_fn00:

	; if bit 7 is set, the diskette drive indicated by the lower 7 bits
	; will reset then the hard disk will follow; return code in AH is
	; for the drive requested
;	push ax
;	push dx
;	and dl, 0x7F
;	int NEWINT13
;	pop dx
;	pop ax

	call mem_clearFlags

	call card_init
	jc .init_failed

.init_ok:
	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_NO_ERROR
		mov [0x41], ah
	pop ds
	jmp int13_iret_clc

.init_failed:
	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_FIXED_DISK_RESET_FAILED
		mov [0x41], ah
	pop ds
	jmp int13_iret_stc


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn01: Disk status
	;
	; returns the status byte located at 40:41 in the BIOS Data Area
	;
int13h_fn01:
	; Return with AL = status
	push ds
	mov ax, 0x40
	mov ds, ax
	mov al, [ds:0x41]
	pop ds
	mov ah, 0x01
	jmp int13_iret_clc

%ifdef TRACE_INT
trace_fn02_params:
	push dx
	mov dl, '>'
	call putchar
	mov dl, al
	call printHexByte
	mov dl, '|'
	call putchar
	mov dx, cx
	call printHexWord
	mov dl, '|'
	call putchar
	pop dx
	push dx
	call printHexWord
	mov dl, '<'
	call putchar
	pop dx
	ret

traceBlockNo:
	push dx
	mov dl, '{'
	call putchar
	mov dx, ax
	call printHexWord
	mov dx, bx
	call printHexWord
	mov dl, '}'
	call putchar
	pop dx
	ret
%endif


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn02: Read Disk Sectors
	;
	;	AL = number of sectors to read (1-128 dec.)
	;	CH = track/cylinder number  (0-1023 dec., see below)
	;	CL = sector number  (1-17 dec.)
	;	DH = head number  (0-15 dec.)
	;	DL = drive number (0=A:, 1=2nd floppy, 80h=drive 0, 81h=drive 1)
	;	ES:BX = pointer to buffer
	;
	; Return AH status, AL sectors read, CF...
	;
int13h_fn02:
	push bx
	push cx
	push dx
	push di

%ifdef TRACE_INT
	call trace_fn02_params
%endif


	push ax	; Save AX to retreive sectors to read at the end

	xor ah, ah	; Make sure AH is 0
	mov bp, ax	; Keep a copy of AX
	mov di, bx	; Keep a copy of the destination offset

	call geo2block

%ifdef TRACE_INT
	call traceBlockNo
%endif

	; AX:BX now points to 32 bit block. We need the block
	; count in CX.
	mov cx, bp	; AL contained the number of sector to read
	xor ch, ch

	push ds
		mov bp, es
		mov ds, bp
		mov bp, di
		call card_readSectors
	pop ds
	jc .timeout

	; Done!
	jmp .done

.timeout:
	pop bx ; Retreive original AX value

	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_FIXED_DISK_DRV_NOT_READY
		mov [0x41], ah
	pop ds

	mov al, 0 ; no sectors were read

	pop di
	pop dx
	pop cx
	pop bx

	jmp int13_iret_stc


.error:
	pop bx ; Retreive original AX value

	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_SECTOR_NOT_FOUND
		mov [0x41], ah
	pop ds

	mov al, 0 ; no sectors were read

	pop di
	pop dx
	pop cx
	pop bx

	jmp int13_iret_stc

.done:
	pop bx ; Retreive original AX value

	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_NO_ERROR
		mov [0x41], ah
	pop ds

	mov al, bl	; number of sectors read = request

	; fallthrough to return_clc below

.return_clc:
	pop di
	pop dx
	pop cx
	pop bx
	jmp int13_iret_clc

.return_stc:
	pop di
	pop dx
	pop cx
	pop bx

	jmp int13_iret_stc


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn03: Write Disk Sectors
	;
int13h_fn03:
	;	AL = number of sectors to write  (1-128 dec.)
	;	CX = track/cylinder number, sector number
	;	DH = head number  (0-15 dec.)
	;	DL = drive number
	;	ES:BX = pointer to buffer
	;
	;	Returns status in AH
	;	CF=0 on success
	push bx
	push cx
	push dx
	push si

%ifdef TRACE_INT
	call trace_fn02_params
%endif


	push ax	; Save AX to retreive sectors to read at the end

	and al, al	; Check number of sectors to write
	jz .zero_write	; Protect against writing 65535 sectors if zero is received


.nonzero_count:

	xor ah, ah	; Make sure AH is 0
	mov bp, ax	; Keep a copy of AX (sector count)
	mov si, bx	; Keep a copy of the source offset

	call geo2block
	call blockToByteAddress		; TODO : Only for byte addressed cards

	; AX:BX now points to 32 bit block. We need the block
	; count in CX.
	mov cx, bp	; AL contained the number of sector to read
	xor ch, ch

.next_block:
	; card_cmd24 args:
	;   ES = Source segment
	;   SI = Source offset
	;	AX = block number (31-16)
	;	BX = block number (15-0)
	; return:
	;	Carry set on timeout
	;	DL
	call card_cmd24
	cmp dl, 0x05
	jne .error

	add si, 512	; Advance in buffer
	add bx, 512	; Increment block number	; TODO : Support block addressed cards
	adc ax, 0

	loop .next_block

	; all written!
	jmp .done


.timeout:
	pop bx ; Retreive original AX value

	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_FIXED_DISK_DRV_NOT_READY
		mov [0x41], ah
	pop ds

	mov al, 0 ; no sectors were written
	jmp .return_stc

.error:
	pop bx ; Retreive original AX value
	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_SECTOR_NOT_FOUND
		mov [0x41], ah
	pop ds
	mov al, 0 ; no sectors were written
	jmp .return_stc


.zero_write:
	pop bx ; Retreive original AX value
	push dx
		printString "!Z!"
	pop dx
	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_BAD_COMMAND
		mov [0x41], ah
	pop ds
	xor al, al	; No sectors were written
	jmp .return_stc


.done:
	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_NO_ERROR
		mov [0x41], ah
	pop ds

	pop bx	; Retreive original AX value
	mov al, bl	; number of sectors read = request

	; Fallthrough to return_clc below

.return_clc:
	pop si
	pop dx
	pop cx
	pop bx
	jmp int13_iret_clc

.return_stc:
	pop si
	pop dx
	pop cx
	pop bx
	jmp int13_iret_stc


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn04 : Verify disk sectors
	;
int13h_fn04:
	; TODO : Verify sectors by reading from the card and dropping the data?
	; For now, fake an instant success...
	mov ah, 0x00
	jmp int13_iret_clc

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn05: Format Disk Track
	;
	; AL = Interleave value
	; ES:BX = 512-byte format buffer
	; CX : Cylinder
	; DH : Head
	; DL : Drive
	;
int13h_fn05:
	push ax
	push bx
	push cx
	push es
	push si

	and cx, ~0x1F	; Make sure "sector number" bits are ignored.
	or cx, 1		; Set sector number to 1 for geo2block

	; Source buffer of zeroes ES:SI for card_cmd24
	mov si, formatted_sector
	mov bx, ds
	mov es, bx

	call geo2block	; Compute block number and store in AX, BX for card_cmd24 below
	call blockToByteAddress

	mov cx, GEO_SECTORS_PER_TRACK
.format_loop:
	; card_cmd24 args:
	;   ES = Source segment
	;   SI = Source offset
	;	AX = block number (31-16)
	;	BX = block number (15-0)
	; return:
	;	Carry set on timeout
	;	DL
	call card_cmd24

	; TODO : Add error handling

	; Increment block number
	add bx, 512	; TODO : Support cards
	adc ax, 0

	loop .format_loop

	pop si
	pop es
	pop cx
	pop bx
	pop ax

	; Return with success.
	mov ah, 0x00
	jmp int13_iret_clc


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn06: FORMAT TRACK AND SET BAD SECTOR FLAGS
	; int13h_fn07: FORMAT DRIVE STARTING AT GIVEN TRACK
	;
int13h_fn06:
int13h_fn07:
	mov bx, ax
	jmp panic

	; Default for unimplemented or unsupported: Return with Carry
	jmp int13_iret_stc


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn08: Get Current Drive Parameters
	;
int13h_fn08:

	push ds
		mov ax, 0x40
		mov ds, ax
		mov ah, STATUS_NO_ERROR
		mov al, 0
		mov [0x41], ah
	pop ds
	mov ah, STATUS_NO_ERROR
	mov bl, CMOS_DRIVE_TYPE
	mov cx, (((GEO_CYLINDERS-1) & 0xFF) << 8) | (((GEO_CYLINDERS-1) & 0x300) >> 2) | GEO_SECTORS_PER_TRACK
	mov dh, GEO_HEADS - 1	; returned value is max head number
	mov dl, 1	; TODO : Floppies + Hard drives???


	jmp int13_iret_clc


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; int13h_fn18: Set Media Type for Format
	;
int13h_fn18:
	;
	; Apparently this should be called before a format operation
	; to set the controller for the correct drive speed and
	; track-stepping option.
	;
	; Clearly not applicable to a flash card. Just ignore it.
	;
	mov ah, STATUS_NO_ERROR
	jmp int13_iret_clc


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; Unhandled calls lead to panic
	;
int13h_fn09:
int13h_fn0a:
int13h_fn0b:
int13h_fn0c:
int13h_fn0d:
int13h_fn0e:
int13h_fn0f:
int13h_fn10:
int13h_fn11:
int13h_fn12:
int13h_fn13:
int13h_fn14:
int13h_fn15:
int13h_fn16:
int13h_fn17:
int13h_fn19:
int13h_fn1a:
	mov bx, ax
	jmp panic

	; Default for unimplemented or unsupported: Return with Carry
	jmp int13_iret_stc


	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; cmd1_hook : Called by card_init to indicate CMD1 was used. (MMC card)
	;
cmd1_hook:
	push ax
	call mem_getFlags
	or al, MEMFLAG_CMD1
	call mem_setFlags
	pop ax
	ret


section .data

	; Data written to "formatted" sectors
formatted_sector: times 512 db 0
