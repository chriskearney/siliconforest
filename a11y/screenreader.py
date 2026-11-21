"""
a11y/screenreader.py — SiliconForest Screen Reader (Phase 2)

Starts the AXUIServer daemon and the AX observer together.
On macOS: uses the real AXUIElement API (axreader.py) for testing.
On SiliconForest: AXUIServer receives events from AppKit via Unix socket.

Usage:
    python3 a11y/screenreader.py [--braille] [--verbose]
"""

import asyncio
import logging
import os
import subprocess
import sys
import argparse

logger = logging.getLogger("screenreader")

SOCKET_PATH = "/tmp/com.siliconforest.axuiserver"
A11Y_DIR = os.path.dirname(os.path.abspath(__file__))


async def run_axserver(braille: bool, verbose: bool):
    """Start the AXUIServer daemon as a coroutine."""
    # Import and run inline (same process) instead of subprocess for clean shutdown
    sys.path.insert(0, os.path.dirname(A11Y_DIR))
    from a11y.axserver import AXEventDispatcher, AXServer

    dispatcher = AXEventDispatcher(
        use_tts=True,
        use_braille=braille,
        verbose=verbose,
    )
    await dispatcher.setup()
    server = AXServer(dispatcher)
    await server.start()
    return server


async def run_ax_observer():
    """
    On macOS: run axreader.py to observe real AXUIElement events and forward
    them to the AXUIServer socket (bridging Apple AX → our daemon).
    On SiliconForest: AppKit pushes events directly; this is a no-op.
    """
    is_siliconforest = not os.path.exists("/System/Library/Frameworks/AppKit.framework")
    if is_siliconforest:
        logger.info("SiliconForest mode: AppKit pushes AX events directly to socket")
        return

    # macOS: run axreader in a subprocess, pipe its JSON output to our socket
    logger.info("macOS mode: bridging AXUIElement observer → AXUIServer socket")
    axreader = os.path.join(A11Y_DIR, "axreader.py")
    if not os.path.exists(axreader):
        logger.warning("axreader.py not found — AX observer disabled")
        return

    try:
        proc = await asyncio.create_subprocess_exec(
            sys.executable, axreader, "--json-socket", SOCKET_PATH,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()
    except Exception as e:
        logger.warning(f"AX observer error: {e}")


async def main():
    parser = argparse.ArgumentParser(description="SiliconForest Screen Reader")
    parser.add_argument("--braille",   action="store_true", help="Enable Braille display output")
    parser.add_argument("--verbose",   action="store_true", help="Print all AX events")
    parser.add_argument("--log-level", default="INFO",      help="DEBUG/INFO/WARNING")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    logger.info("SiliconForest Screen Reader starting")
    logger.info(f"  TTS:    eSpeak-NG")
    logger.info(f"  Braille: {'BRLTTY' if args.braille else 'disabled (use --braille)'}")
    logger.info(f"  Socket: {SOCKET_PATH}")

    server = await run_axserver(braille=args.braille, verbose=args.verbose)

    try:
        await run_ax_observer()
        # Keep server running
        await asyncio.Event().wait()
    except asyncio.CancelledError:
        pass
    finally:
        await server.stop()
        logger.info("Screen reader stopped")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
