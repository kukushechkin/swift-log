"""LLDB helper scripts for swift-log debugging."""

import lldb
import re


# Global state for filtering toggle
_filter_enabled = True


def filtered_backtrace(debugger, command, result, internal_dict):
    """Display backtrace with optional task-local frame filtering.

    Usage: bt [count]
    """
    filter_patterns = [
        r'TaskLocal\.withValue',
        r'GlobalLoggerContext\.withTaskLocalLoggerInline',
        r'closure #\d+ in static GlobalLoggerContext\.withTaskLocalLoggerInline'
    ]

    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()

    # Parse optional frame count argument
    max_frames = None
    if command:
        try:
            max_frames = int(command)
        except ValueError:
            pass

    frame_count = 0
    for frame in thread:
        if max_frames and frame_count >= max_frames:
            break

        frame_name = frame.GetFunctionName()
        should_skip = False

        if _filter_enabled and frame_name:
            should_skip = any(re.search(pattern, frame_name) for pattern in filter_patterns)

        if not should_skip:
            print(f"frame #{frame.GetFrameID()}: {frame}")
            frame_count += 1


def toggle_filter(debugger, command, result, internal_dict):
    """Toggle task-local frame filtering on/off.

    Usage: toggle-tasklocal-frames
    """
    global _filter_enabled
    _filter_enabled = not _filter_enabled
    status = "enabled" if _filter_enabled else "disabled"
    print(f"Task-local frame filtering {status}")


def __lldb_init_module(debugger, internal_dict):
    """Initialize module and register commands."""
    # Override bt command with filtered version
    debugger.HandleCommand('command script add -f swift_logging_frames_filtering.filtered_backtrace bt')
    debugger.HandleCommand('command script add -f swift_logging_frames_filtering.toggle_filter toggle-tasklocal-frames')
    # Preserve original bt as btu (backtrace unfiltered)
    debugger.HandleCommand('command alias btu _regexp-bt')
    print('swift-log LLDB helpers loaded.')
    print('  bt - filtered backtrace (task-local frames hidden by default)')
    print('  btu - unfiltered backtrace (shows all frames)')
    print('  toggle-tasklocal-frames - toggle filtering on/off')
