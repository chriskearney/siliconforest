# ApplicationServices printing APIs for Preview

The private wrapper builds the pinned PureDarwin PrintCore implementation
with the saved-settings, session-data, printer lookup, and scale APIs used
by Preview. It reexports the installed ApplicationServices for the
remaining APIs. Print settings, page formats, and sessions retain their
existing dictionary representation so callers can share the same objects.

The native probe reads a binary property list, observes the imported
copies through the existing PrintCore API, checks isolated session values
and scale validation, and exercises the generic print-to-file printer.
