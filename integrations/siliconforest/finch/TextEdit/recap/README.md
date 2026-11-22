# TextEdit's Recap classes

TextEdit links `RPTResizeTestParameters` and `RPTScrollViewTestParameters`.
The RecapPerformanceTesting image Preview uses defines `RPTTestRunner` and
`RPTActivationTestParameters` only. Dyld looks for the missing classes in
that image, so they cannot be supplied from the side.

`RecapTextEdit.m` defines the two classes and nothing else. `build.sh`
links them in front of a copy of Preview's Recap library. The copy is
renamed `@loader_path/RecapPerformanceTesting.sf-under`. The front's
install name is `RecapPerformanceTesting.sf-textedit`. TextEdit finds the
front through `DYLD_FRAMEWORK_PATH`. Preview's copy is not modified.
Built binaries are not committed.
