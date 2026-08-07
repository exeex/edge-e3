# Edge Apache License — edge-e3 Draft

The Edge Apache License is being drafted for the hardware contained in this
directory. This version does not include a license grant for project-owned
source code, hardware designs, documentation, or other materials. Previously
distributed versions remain governed by the license terms that accompanied
them.

The intended model permits simulation and FPGA implementation with any number
of cores and no license fee. For manufactured silicon, the **Edge Apache
License** applies only when a physical package contains exactly one edge-e3
core. That license will inherit Apache-style rights and obligations, including
commercial use, modification, and distribution, without a commercial license
fee.

Every other manufactured-silicon configuration is governed by a separate
commercial license. For a package containing `n3` edge-e3 cores, `n4` edge-e4
cores, and `n5` edge-e5 cores, the intended fee is:

```text
max(n3 + 4n4 + 16n5 - 1, 0) X
```

This includes packages with multiple edge-e3 cores, any edge-e4 or edge-e5
core, and mixed-core packages.

The Edge Apache License is a custom edge-e3 license, not the Apache License,
and is not issued or endorsed by the Apache Software Foundation. This summary
is not a license grant and does not replace the forthcoming complete terms.

Third-party dependencies retain their respective upstream licenses.
