# Composition root

Expose one public `configureDependencies()` function and split registration into core and feature modules. Registration constructs objects only. Start listeners, polling, deep-link handlers, and other side effects in a separate bootstrap phase.
