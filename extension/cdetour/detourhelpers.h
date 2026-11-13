/**
 * vim: set ts=4 :
 * =============================================================================
 * SourceMod
 * Copyright (C) 2004-2010 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id: detourhelpers.h 248 2008-08-27 00:56:22Z pred $
 */

#ifndef _INCLUDE_SOURCEMOD_DETOURHELPERS_H_
#define _INCLUDE_SOURCEMOD_DETOURHELPERS_H_

#if defined PLATFORM_POSIX
#include <sys/mman.h>
#ifndef PAGE_SIZE
#define	PAGE_SIZE	4096
#endif
#define ALIGN(ar) ((long)ar & ~(PAGE_SIZE-1))
#define	PAGE_EXECUTE_READWRITE	PROT_READ|PROT_WRITE|PROT_EXEC
#endif

#include <jit/x86/x86_macros.h>
#include "MemoryPatch.h"

inline bool ProtectMemory(void *addr, int length, int prot)
{
	return length > 0 && TryProtectMemory(addr, static_cast<size_t>(length), prot);
}

inline bool PatchRelJump32(unsigned char *target, void *callback)
{
	patch_t jump;
	jump.bytes = 5;
	jump.patch[0] = IA32_JMP_IMM32;
	const int32_t displacement = static_cast<int32_t>(reinterpret_cast<uintptr_t>(callback) -
		(reinterpret_cast<uintptr_t>(target) + 5));
	std::memcpy(jump.patch + 1, &displacement, sizeof(displacement));
	return ApplyPatch(target, 0, &jump, nullptr);
}

inline bool PatchAbsJump64(unsigned char *target, void *callback)
{
	patch_t jump;
	size_t i = 0;
	jump.patch[i++] = IA32_PUSH_IMM32;
	const uint64_t address = reinterpret_cast<uintptr_t>(callback);
	const uint32_t low = static_cast<uint32_t>(address);
	std::memcpy(jump.patch + i, &low, sizeof(low)); i += sizeof(low);
	const uint32_t high = static_cast<uint32_t>(address >> 32);
	if (high) {
		jump.patch[i++] = IA32_MOV_RM_IMM32;
		jump.patch[i++] = ia32_modrm(MOD_DISP8, 0, kREG_SIB);
		jump.patch[i++] = ia32_sib(NOSCALE, kREG_NOIDX, kREG_ESP);
		jump.patch[i++] = 0x04;
		std::memcpy(jump.patch + i, &high, sizeof(high)); i += sizeof(high);
	}
	jump.patch[i++] = IA32_RET;
	jump.bytes = i;
	return ApplyPatch(target, 0, &jump, nullptr);
}

inline bool DoGatePatch(unsigned char *target, void *callback)
{
#if defined(_WIN64) || defined(__x86_64__)
	const int64_t diff = int64_t(callback) - (int64_t(target) + 5);
	if (diff >= (std::numeric_limits<int32_t>::min)() && diff <= (std::numeric_limits<int32_t>::max)())
		return PatchRelJump32(target, callback);
	return PatchAbsJump64(target, callback);
#else
	return PatchRelJump32(target, callback);
#endif
}

#endif //_INCLUDE_SOURCEMOD_DETOURHELPERS_H_
