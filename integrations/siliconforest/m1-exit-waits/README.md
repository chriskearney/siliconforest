# Processes stuck in exit: kern.sf_exitwait (kernel 51)

SF-AH item 25: VLC (official build, our frameworks) stays in exit after GPU-heavy runs with
corner drags and TERM (once TERM then KILL): `ps` state `?E`/`?Es`, ppid 1, no threads listed,
`task_for_pid` failing, one DRM clone slot (`kern.sf_dri.clone_slots used`) and its Wayland
connection still held. A restart once hung in shutdown on it and needed an external reset
(18 Nov 12:2xZ); the next restart with a stuck VLC (pid 1961) completed by itself. Three cases on
18 Nov: 11:35Z (rM3, NSOpenGLView + `SF_CGL_LEND=1`, TERM then KILL at 5 s), 12:53Z (rM9, the same
output, TERM only, no exception-port wrapper), 15:48Z (d1, pid 39503, the default output on the
QuartzCore 0331 GPU path: CAOpenGLLayer copies into GPU-storage IOSurfaces, dma-buf presentation).
Dozens of other runs exited cleanly.

Nothing on the M1 can say where such a process waits: `sample` needs `task_for_pid`, `ps`
shows no wait channel, there is no stackshot reader or dtrace. `kernel.patch` adds one.

## The report

Off by default; nothing runs until asked; root only.

| | |
|---|---|
| `sysctl kern.sf_exitwait.report` | every process in exit (P_LEXIT, not yet a zombie) |
| `sysctl kern.sf_exitwait.log=1` | the same report into the kernel log (`dmesg`) |
| `sysctl kern.sf_exitwait.pid=N` | also process N in any state (`-1`: every process) |
| `sysctl kern.sf_exitwait.kernel=1` | also kernel_task's threads (DRM scheduler, LinuxKPI taskqueues, firmware workers) |
| `sysctl kern.sf_exitwait.at_shutdown=1`, boot-arg `sf_exitwait_shutdown=1` | the report on the console after `proc_shutdown`, before file systems are unmounted |

Per process: pid, ppid, name, `p_stat`, `p_lflag` (`exit` = P_LEXIT, `proc_exit` = P_LPEXIT: the
last thread has reached `proc_exit`), proc reference count and bits (`dead`, `draining` =
`proc_refdrain` running), exit status, size of the descriptor table (0 once `fdt_invalidate` has
released it), and the task: active, halting, ipc, thread counts. Per thread: tid, state
(`wait`, `unint`, `run`, `term`), priority, block hint (xnu `block_hint.h`: 1 kernel mutex,
6 semaphore, 7–9 rw lock, ...), wait result, seconds since it left a processor, wait event and
wait queue (`VM_KERNEL_UNSLIDE_OR_PERM`, as stackshot: unslid inside the kernel collection,
permuted otherwise; equal values are the same object), the tid that holds the kernel mutex or rw
lock it waits for, its msleep message, its name, continuation, and `bt` lines: the kernel frame
chain as unslid return addresses, innermost first. The shape (values illustrative):

    pid 39503 ppid 1 VLC stat 2 lflag 0x... exit refs 1 bits 0x.. dead xstat 0x.. fds 256 zombproc
     task active 0 halting 0 ipc 0 threads 1 (active 0) suspend 1; listed 1, terminated 0
     tid 123456 state 0x9 wait unint pri 31 hint 0 res 0 blocked 3600.123 s event 0x... waitq 0x...
       owner 0 wmesg - [exit thread]
      bt 0xfffffe00070f1234 0xfffffe00070e5678 ...

Names for the addresses, on the workstation:

    nix-build ../m1-kernel51/build-kc.nix --no-out-link            # the collection that booted
    nix-build ../m1-kernel51/build-kc.nix -A members --no-out-link # its members, with symbols
    python3 symbolicate.py COLLECTION MEMBERS report.txt \
        --map <SFAgx derivation>/nix-support/SFAgx.map --map <SFDcp derivation>/nix-support/SFDcp.map

Each `bt` address gets `[<bundle> <symbol>+0x<offset>]` from the member's own symbol table
(local symbols included, so Rust and static C functions are named). SFAgx and SFDcp are built
without local symbols: their link maps (`--map`) name those functions. On the M1 (kernel 51,
18 November, `runs/kexit/m1/selftest-*`) every frame of 140 kernel threads was named that way,
e.g. an SFAgx worker: `machine_switch_context` ← `thread_invoke` ← `thread_block_reason` ←
`sfos_wait_sleep` ← `acquire_sem_etc` ← `callout_thread` ← `spawn_trampoline` ← `thread_entry`. Checked against kernel 50's
collection: 2,624 text symbols of the collection's own symbol tables resolve to the same name
at offset 0 through the members; the only mismatches are the 48 of ext4, whose member there was
kernel 48's (the one member kernel 50 changed).

How it avoids waiting on what it reports: the process lists are walked under `proc_list_lock`
without process references (a process past `proc_refdrain` cannot take one) and include
`zombproc`, where a process in exit already is (an `allproc` walk does not see it); tasks are held by task references;
the global thread lists are taken with a try-lock (EBUSY after ~100 ms); every thread is held by a
reference; every word of another thread's stack, of a lock and of a thread name is read with
`ml_nofault_copy()`, a frame chain only inside that thread's kernel stack and only upwards. A
thread that moved while it was read is flagged `[moved]`; a chain that leaves the stack is
`[truncated]`. Nothing in any process is changed. `test-exitwait.py` compiles the actual frame
walk and lock-owner bodies out of `kernel.patch` against stubs (ASan/UBSan): chains that leave
the stack, loop, are misaligned or reach an unmapped page stop; the frame limit holds; return
addresses outside the image are 0; mutex and rw-lock owners come from the ctid table; a destroyed
mutex or an unreadable event has none. Four mutations of those bodies each fail it.

## Where a thread can sleep for good in exit and close (offline, from source)

Kernel 50 = xnu-12377 + the lab series (`m1-kernel48/build-kc.nix`), SFAgx = drm/asahi of
linux-aurora 6a08a08e (G13 build) on FreeBSD LinuxKPI + drm-kmod at Linux 7.2. LinuxKPI sleeps
become `assert_wait` + `thread_block` (`sf_fbsd_os.cpp sfos_wait_sleep`): `THREAD_ABORTSAFE` for
the `_sig` variants, `THREAD_UNINT` otherwise; mutexes are `lck_mtx`/`lck_rw`. Since kernel 48
(`m1-killable-waits`) `signal_pending()` and `current_exiting()` answer yes in an exiting process,
so interruptible Linux wait loops end at exit. Kernel threads (DRM scheduler work, taskqueues)
take no signals: their interruptible waits are effectively uninterruptible.

The order of an exit: the exiting thread runs `exit_with_reason` → `proc_prepareexit` (the proc
moves to `zombproc`, P_REF_DEAD) → `task_terminate_internal` (aborts the other threads; then
`ipc_space_terminate`, where kobject no-senders run inline on this thread: fileports and IOKit
user clients; then `vm_map_terminate`). Each other thread terminates when it leaves its kernel
wait. The last one runs `proc_exit` → `proc_refdrain` → `fdt_invalidate` (descriptors closed from
the highest number down) → zombie. A stuck process with its DRM slot and Wayland socket still
held is therefore stuck before or inside the close of its DRM descriptor (inferred: the DRM
device is opened after the Wayland connection, so it has the higher number and closes first).

| # | Where (source) | Sleep | Woken by | Can lose its waker when a GPU client dies mid-work? |
|---|---|---|---|---|
| 1 | `drm_sched_entity_kill`: `wait_for_completion(&entity->entity_idle)` (sched_entity.c:328), from Queue drop → `drm_sched_entity_destroy`/`_fini` (QUEUE_DESTROY ioctl at GL context teardown, or File drop at DRM close) | UNINT, no timeout | the queue's scheduler run-job work, `complete_all` after `run_job` returns or when it finds no job (sched_main.c:1060/1076) | **Yes**, if that queue's `run_job` (asahi `QueueJob::run`: registration guard, `start_op`, the work queue's `inner` mutex in `submit()`, the pipe mutex and RTKit mutex in `run_job`) is blocked; each queue has its own scheduler, so other clients keep drawing |
| 2 | `drm_sched_fini`: `disable_work_sync(run_job)`, `disable_work_sync(free_job)`, `cancel_delayed_work_sync(work_tdr)`, `destroy_workqueue` (sched_main.c), from SchedulerOwner drop | UNINT | the running work item returning | **Yes**, same cause as 1 (a blocked `run_job`/`free_job`/timeout handler) |
| 3 | `drm_sched_entity_flush` (sched_entity.c:401/406) | exiting: timed (`MAX_WAIT_SCHED_ENTITY_Q_EMPTY`); else killable | `wake_up(&sched->job_scheduled)` | No: bounded / ends at exit |
| 4 | asahi `mmu/lifetime.rs`: `retain_job` waits while `draining` (l.425), `quarantine` and `unmap_user_ranges` wait for `commits == 0` (l.120, 617) | UNINT CondVar | `drain_mappings` finishing; `MappingCommit` drop | Not seen: `unmap_user_ranges` is G17-only (`vm.status()`); `retain_job` (SUBMIT) depends on a drain that needs GPUVM/resv locks |
| 5 | asahi `mmu/residency.rs`: `enter_retirement`, `Gate::close` wait while `busy` (l.156, 185) | UNINT CondVar | restore/reclaim finishing | Unlikely: the gate serves pressure reclaim of idle VMs |
| 6 | GEM handle close at DRM close (`drm_gem_release` → asahi `close` → `drop_mappings` → `gpuvm.exec_lock`), dma-buf release (`sf_lfile_close` → `sf_lkpi_fput` → `drm_gem_dmabuf_release` → GEM free), VM drop: `dma_resv`/ww-mutex and GPUVM mutexes | UNINT lock | the holder's unlock | Only through a holder that is itself stuck (e.g. a run-job work or free-job work holding a VM/BO lock) |
| 7 | asahi work-queue `Job::drop` and `submit()`: `wq.inner` mutex (workqueue.rs:555, 441); `new_job` holds it while it waits for an event slot (`slotalloc` `wait_interruptible`, l.283) | lock UNINT; slot wait interruptible (user thread) / effectively UNINT (kernel thread) | unlock; a slot freed when a work queue goes idle | A user thread in SUBMIT is aborted at exit and lets go; a kernel thread that waits for a slot while holding `inner` would block 1/2 |
| 8 | `fileproc_drain` "fpdrain" (kern_descrip.c:1711) in `fdt_invalidate` | UNINT msleep | `fp_drop` of another I/O reference | Only with a leaked `fp_lookup` reference (every sf_lfile lookup drops its own) |
| 9 | `proc_refdrain` "proc_refwait" (kern_proc.c:909) | UNINT | `proc_rele` of the last other holder | Only if a reference holder waits on the dying process (not GPU) |
| 10 | IOSurface user client close in `ipc_space_terminate`: `IOSurfaceRootUserClient::clientClose` → `thread_call_cancel_wait(fCompletionCall)` (IOSurfaceRoot.cpp:1253) | UNINT | the completion thread call returning | If that thread call blocks; it runs on the exit thread before any descriptor is closed |
| 11 | Fileport (GPU-storage IOSurface) last send right in `ipc_space_terminate` → `fileport_releasefg` → `sf_lfile_close` → dma-buf release (as 6), inline on the exit thread | as 6 | as 6 | as 6 |
| 12 | GEM and dma-buf CPU mappings in `vm_map_terminate` | none inline: both release callbacks go to a workqueue (`drm_gem_shmem_sf_unmap`, `sf_lfile_mapping_release`) | — | No |
| 13 | Firmware channel `TxChannel::put` with a full ring (channel.rs:157) | `fsleep(8 ms)` loop, no bound | the firmware consuming the ring | Only with a stalled firmware ring (the GPU kept working for others: not seen) |
| 14 | Interruptible LinuxKPI waits of the client's own threads (syncobj/fence waits, CondVar `wait_interruptible`) | ABORTSAFE | abort at exit; `signal_pending` yes since kernel 48 | No |

Most likely, inferred and not verified: rows 1–2. A queue teardown (Mesa's GL context
destruction on TERM, or the DRM descriptor's close in exit) waits without timeout and
uninterruptibly for its scheduler's run-job work, and that work is blocked in asahi's `run_job`
path; every GPU-heavy client on the shared-buffer paths runs into it only when its teardown
races a job still on its way to the firmware, which fits "after GPU-heavy runs with drags", a
TERM during a 5–6 s teardown, and dozens of clean exits. What would block `run_job` is not
established from the source: the report's `kernel=1` view of the DRM scheduler workers decides it.

## Reproduce and read (for the coordinator, on kernel 51)

0. First, that it reads real stacks on this machine: `sysctl kern.sf_exitwait.pid=$(pgrep -x sshd |
   head -1); sysctl kern.sf_exitwait.report; sysctl kern.sf_exitwait.pid=0`. Expected: the
   listener's threads waiting in Mach message or kevent paths, frames that symbolicate to them.
   Done on kernel 51 (18 November): sshd's listener waits in `select` (continuation
   `_sleep_continue`, no stack); kernel_task's 140 threads give full named frame chains.
1. Before the run: `sysctl kern.sf_exitwait.kernel=1` (the report stays off until read).
2. VLC drag session as rM9/d1; on a stuck exit (`ps -axo pid,ppid,stat,command | grep '?E'`):
   `sysctl kern.sf_exitwait.report > /private/var/tmp/exitwait-$(date +%s).txt` (twice, a minute
   apart: the frames that stay are the wait). `sysctl kern.sf_exitwait.pid=<compositor pid>` and a
   third read adds the compositor.
3. On the workstation: `symbolicate.py` as above.
4. Before the restart, with a UART reader on the M5: `sysctl kern.sf_exitwait.at_shutdown=1`;
   with `sfhaltlog=1` too the console shows each shutdown step and the report right after
   `proc_shutdown`.
