# E3 physical targets

This tree is the source of truth for OpenROAD inputs owned by E3 RTL. The
repository-level runner and PDK defaults remain in the integration repository.

Each target keeps its filelists, physical probes, pin constraints, profiles,
and focused physical tests together. Paths inside runnable files are rooted at
the integration workspace mounted as `/work`.
