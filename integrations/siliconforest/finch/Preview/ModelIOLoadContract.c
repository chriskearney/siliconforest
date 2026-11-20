/* SPDX-License-Identifier: MIT */
/* Load contract only, NOT a ModelIO implementation.
 * Preview and its 118 currently resolvable images import no ModelIO API.
 * Export no Apple function/class and advertise no asset capability. A future
 * typed ModelIO import must fail binding until a real provider implements it.
 */
const unsigned SFModelIOImplementedAPICount = 0;
const char SFModelIOLoadContractScope[] =
    "Required library identity only; ModelIO asset APIs are unavailable.";
