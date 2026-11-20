# CoreFoundation keys and test logging for Preview

The private framework preserves the URL keys in the QuickTime additions
and adds the four keys Preview imports. Their string values and the
`CFLogTest` behavior come from the pinned Finch source.

The current SiliconForest CoreFoundation framework image is staged as
`CoreFoundation.sf-under` next to the additions. The probe checks key
identity by value, console formatting, and sequential writes to the
private test home's `Library/Logs/CFLogTest.log`.
